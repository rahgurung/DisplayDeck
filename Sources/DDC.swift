import Foundation
import IOKit

// Private IOKit symbols used for DDC/CI over I²C on Apple Silicon.
@_silgen_name("IOAVServiceCreateWithService")
private func IOAVServiceCreateWithService(_ allocator: CFAllocator?, _ service: io_service_t) -> Unmanaged<CFTypeRef>?
@_silgen_name("IOAVServiceReadI2C")
private func IOAVServiceReadI2C(_ service: CFTypeRef, _ chipAddress: UInt32, _ offset: UInt32, _ buffer: UnsafeMutableRawPointer, _ size: UInt32) -> IOReturn
@_silgen_name("IOAVServiceWriteI2C")
private func IOAVServiceWriteI2C(_ service: CFTypeRef, _ chipAddress: UInt32, _ dataAddress: UInt32, _ buffer: UnsafeMutableRawPointer, _ size: UInt32) -> IOReturn

enum VCP: UInt8 {
    case brightness = 0x10
    case contrast = 0x12
    case volume = 0x62
    case mute = 0x8D
}

/// One DDC/CI connection to an external monitor. All I/O runs on a private serial queue;
/// rapid slider updates are coalesced so only the latest value per control is sent.
final class DDCChannel {
    private let service: CFTypeRef
    private let queue = DispatchQueue(label: "DisplayDeck.ddc")
    private let lock = NSLock()
    private var pending: [UInt8: UInt16] = [:]

    private static let chipAddress: UInt32 = 0x37
    private static let dataAddress: UInt32 = 0x51

    init?(ioService: io_service_t) {
        guard let s = IOAVServiceCreateWithService(kCFAllocatorDefault, ioService)?.takeRetainedValue() else { return nil }
        service = s
    }

    func set(_ code: VCP, _ value: UInt16) {
        lock.lock()
        let alreadyQueued = pending[code.rawValue] != nil
        pending[code.rawValue] = value
        lock.unlock()
        guard !alreadyQueued else { return }
        queue.async { [self] in
            lock.lock()
            let latest = pending.removeValue(forKey: code.rawValue)
            lock.unlock()
            if let latest { _ = write(code, latest) }
        }
    }

    func read(_ code: VCP, completion: @escaping ((current: UInt16, max: UInt16)?) -> Void) {
        queue.async { [self] in completion(readSync(code)) }
    }

    private func send(_ body: [UInt8]) -> Bool {
        var packet = [UInt8(0x80 | body.count)] + body
        packet.append(packet.reduce(UInt8(0x6E) ^ UInt8(Self.dataAddress), ^))
        // Many monitors drop the first write, so send it twice like MonitorControl does.
        var ok = false
        for _ in 0..<2 {
            usleep(10_000)
            if IOAVServiceWriteI2C(service, Self.chipAddress, Self.dataAddress, &packet, UInt32(packet.count)) == KERN_SUCCESS { ok = true }
        }
        return ok
    }

    private func write(_ code: VCP, _ value: UInt16) -> Bool {
        send([0x03, code.rawValue, UInt8(value >> 8), UInt8(value & 0xFF)])
    }

    private func readSync(_ code: VCP) -> (current: UInt16, max: UInt16)? {
        for _ in 0..<4 {
            guard send([0x01, code.rawValue]) else { continue }
            usleep(50_000)
            var reply = [UInt8](repeating: 0, count: 11)
            guard IOAVServiceReadI2C(service, Self.chipAddress, 0, &reply, UInt32(reply.count)) == KERN_SUCCESS else { continue }
            let checksum = reply[0..<10].reduce(UInt8(0x50), ^)
            if reply[2] == 0x02, reply[3] == 0x00, reply[4] == code.rawValue, reply[10] == checksum {
                let max = UInt16(reply[6]) << 8 | UInt16(reply[7])
                let current = UInt16(reply[8]) << 8 | UInt16(reply[9])
                if max > 0 { return (current, max) }
            }
            usleep(20_000)
        }
        return nil
    }

    /// Walks the IOService plane pairing each external DCPAVServiceProxy with the
    /// ProductAttributes of the framebuffer (AppleCLCD2) that precedes it.
    static func discover() -> [(attributes: [String: Any], channel: DDCChannel)] {
        var results: [(attributes: [String: Any], channel: DDCChannel)] = []
        var iterator = io_iterator_t()
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        guard IORegistryEntryCreateIterator(root, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }

        var lastAttributes: [String: Any]?
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            var nameBuffer = [CChar](repeating: 0, count: 128)
            IORegistryEntryGetName(entry, &nameBuffer)
            let name = String(cString: nameBuffer)

            if name == "AppleCLCD2" || name == "IOMobileFramebufferShim" {
                let attrs = IORegistryEntryCreateCFProperty(entry, "DisplayAttributes" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any]
                lastAttributes = attrs?["ProductAttributes"] as? [String: Any]
            } else if name == "DCPAVServiceProxy" {
                let location = IORegistryEntryCreateCFProperty(entry, "Location" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String
                if location == "External", let attrs = lastAttributes, let channel = DDCChannel(ioService: entry) {
                    results.append((attrs, channel))
                }
                lastAttributes = nil
            }
        }
        return results
    }
}
