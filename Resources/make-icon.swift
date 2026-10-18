// Draws the "Contrast" app icon (one monitor, screen split light and dark) and builds AppIcon.icns.
// Usage: swift Resources/make-icon.swift
import AppKit
import ImageIO
import UniformTypeIdentifiers

let dir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func rgb(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

func roundedRect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> CGPath {
    CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerWidth: r, cornerHeight: r, transform: nil)
}

/// Renders the icon at `size` px, drawing in the 1024-unit design grid with y pointing down.
func render(_ size: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let scale = CGFloat(size) / 1024
    ctx.translateBy(x: 0, y: CGFloat(size))
    ctx.scaleBy(x: scale, y: -scale)
    let white = CGColor(gray: 1, alpha: 1)

    // Background squircle with a vertical blue gradient.
    ctx.saveGState()
    ctx.addPath(roundedRect(100, 100, 824, 824, 185))
    ctx.clip()
    let gradient = CGGradient(colorsSpace: nil, colors: [rgb(0x3E4BF0), rgb(0x1F27A6)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 100), end: CGPoint(x: 0, y: 924), options: [])
    ctx.restoreGState()

    // Monitor outline.
    ctx.addPath(roundedRect(262, 300, 500, 340, 44))
    ctx.setStrokeColor(white)
    ctx.setLineWidth(36)
    ctx.strokePath()

    // Light half of the screen.
    ctx.saveGState()
    ctx.addPath(roundedRect(302, 340, 420, 260, 12))
    ctx.clip()
    ctx.move(to: CGPoint(x: 302, y: 340))
    ctx.addLine(to: CGPoint(x: 722, y: 340))
    ctx.addLine(to: CGPoint(x: 302, y: 600))
    ctx.closePath()
    ctx.setFillColor(white)
    ctx.fillPath()
    ctx.restoreGState()

    // Stand.
    ctx.setFillColor(white)
    ctx.fill(CGRect(x: 482, y: 640, width: 60, height: 54))
    ctx.addPath(roundedRect(402, 690, 220, 32, 16))
    ctx.fillPath()

    return ctx.makeImage()!
}

for points in [16, 32, 128, 256, 512] {
    for factor in [1, 2] {
        let name = factor == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        let dest = CGImageDestinationCreateWithURL(iconset.appendingPathComponent(name) as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, render(points * factor), nil)
        CGImageDestinationFinalize(dest)
    }
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", dir.appendingPathComponent("AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns" : "iconutil failed")
