import Foundation

/// A monitor input (VCP 0x60 value) such as HDMI 1 or DisplayPort 1.
struct InputSource: Identifiable, Hashable {
    let value: UInt8
    var id: UInt8 { value }

    var name: String {
        switch value {
        case 0x01: return "VGA 1"
        case 0x02: return "VGA 2"
        case 0x03: return "DVI 1"
        case 0x04: return "DVI 2"
        case 0x0F: return "DisplayPort 1"
        case 0x10: return "DisplayPort 2"
        case 0x11: return "HDMI 1"
        case 0x12: return "HDMI 2"
        case 0x13: return "HDMI 3"
        case 0x1B: return "USB-C"
        default: return String(format: "Input 0x%02X", value)
        }
    }

    var symbol: String {
        switch value {
        case 0x0F, 0x10: return "display"
        case 0x11, 0x12, 0x13: return "tv"
        case 0x1B: return "cable.connector"
        default: return "rectangle.connected.to.line.below"
        }
    }

    /// Offered when the monitor doesn't list its inputs: the connectors most monitors have.
    static let common: [InputSource] = [0x0F, 0x10, 0x11, 0x12, 0x1B].map(InputSource.init)

    /// The inputs listed for VCP 60 in a capabilities string, e.g. `vcp(10 12 60(0F 11 12) 62)` → DP 1, HDMI 1, HDMI 2.
    static func parse(capabilities: String) -> [InputSource] {
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
                    return hexBytes(text[index..<close]).map(InputSource.init)
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
