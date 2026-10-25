import Foundation

/// A monitor input (VCP 0x60 value) such as HDMI 1 or DisplayPort 1.
struct InputSource: Identifiable, Hashable {
    let value: UInt8
    /// The display's EISA vendor number (CGDisplayVendorNumber), since codes above 0x12 mean different
    /// connectors to different manufacturers.
    let vendor: UInt32
    var id: UInt8 { value }

    /// MCCS only defines codes up to 0x12 and leaves USB-C out entirely, so manufacturers pick their own, and
    /// sometimes per model. These are codes reported by owners of more than one model, or verified on hardware;
    /// anything else shows as "Input 0xNN" until the user renames it.
    private static let vendorNames: [UInt32: [UInt8: String]] = [
        0x09D1: [0x13: "USB-C"],  // BenQ ("BNQ"), verified on the EX271Q
        0x10AC: [0x1B: "USB-C"],  // Dell ("DEL")
        0x1E6D: [0x90: "HDMI 1", 0x91: "HDMI 2", 0xD0: "DisplayPort", 0xD1: "USB-C"],  // LG ("GSM")
        0x22F0: [0x13: "DisplayPort 2"],  // HP ("HWP")
    ]

    var name: String {
        if let name = Self.vendorNames[vendor]?[value] { return name }
        switch value {
        case 0x01: return "VGA 1"
        case 0x02: return "VGA 2"
        case 0x03: return "DVI 1"
        case 0x04: return "DVI 2"
        case 0x05: return "Composite 1"
        case 0x06: return "Composite 2"
        case 0x07: return "S-Video 1"
        case 0x08: return "S-Video 2"
        case 0x0C: return "Component 1"
        case 0x0D: return "Component 2"
        case 0x0E: return "Component 3"
        case 0x0F: return "DisplayPort 1"
        case 0x10: return "DisplayPort 2"
        case 0x11: return "HDMI 1"
        case 0x12: return "HDMI 2"
        default: return String(format: "Input 0x%02X", value)
        }
    }

    var symbol: String {
        if name == "USB-C" { return "cable.connector" }
        if name.hasPrefix("DisplayPort") { return "display" }
        if name.hasPrefix("HDMI") { return "tv" }
        return "rectangle.connected.to.line.below"
    }

    /// Offered when the monitor doesn't list its inputs: the connectors most monitors have, in the manufacturer's
    /// codes where they differ from MCCS, plus USB-C where its code is known.
    static func common(vendor: UInt32) -> [InputSource] {
        let values: [UInt8]
        switch vendor {
        case 0x1E6D: values = [0xD0, 0xD1, 0x90, 0x91]  // LG
        case 0x22F0: values = [0x0F, 0x13, 0x11, 0x12]  // HP
        default: values = [0x0F, 0x10, 0x11, 0x12] + (vendorNames[vendor]?.first { $0.value == "USB-C" }.map { [$0.key] } ?? [])
        }
        return values.map { InputSource(value: $0, vendor: vendor) }
    }

    /// The inputs listed for VCP 60 in a capabilities string, e.g. `vcp(10 12 60(0F 11 12) 62)` → DP 1, HDMI 1, HDMI 2.
    static func parse(capabilities: String, vendor: UInt32) -> [InputSource] {
        let text = capabilities.uppercased()
        guard let vcp = text.range(of: "VCP(") else { return [] }
        // Walk the vcp list at depth 1 looking for the code 60 followed by its own (…) list of values.
        var depth = 1
        var token = ""
        var index = vcp.upperBound
        while index < text.endIndex, depth > 0 {
            let char = text[index]
            index = text.index(after: index)
            switch char {
            case "(":
                // Some monitors pack codes without spaces ("106062("), so match 60 as the last two-digit code.
                if depth == 1, token.count % 2 == 0, token.hasSuffix("60"), let close = text[index...].firstIndex(of: ")") {
                    return hexBytes(text[index..<close]).map { InputSource(value: $0, vendor: vendor) }
                }
                depth += 1
                token = ""
            case ")":
                depth -= 1
                token = ""
            case " ":
                token = ""
            default:
                token.append(char)
            }
        }
        return []
    }

    private static func hexBytes(_ text: Substring) -> [UInt8] {
        text.split(separator: " ").flatMap { chunk in
            stride(from: 0, to: chunk.count - 1, by: 2).compactMap { offset -> UInt8? in
                let start = chunk.index(chunk.startIndex, offsetBy: offset)
                return UInt8(chunk[start..<chunk.index(start, offsetBy: 2)], radix: 16)
            }
        }
    }
}
