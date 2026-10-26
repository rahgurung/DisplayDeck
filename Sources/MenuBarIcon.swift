import AppKit

/// Menu bar template glyph matching the app icon: a monitor whose screen is split light and dark.
enum MenuBarIcon {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { rect in
            // Drawn in a 22-unit grid.
            NSGraphicsContext.current?.cgContext.scaleBy(x: rect.width / 22, y: rect.height / 22)
            NSColor.black.set()

            let frame = NSBezierPath(roundedRect: NSRect(x: 3, y: 4, width: 16, height: 11), xRadius: 2, yRadius: 2)
            frame.lineWidth = 1.6
            frame.stroke()

            let light = NSBezierPath()
            light.move(to: NSPoint(x: 5.4, y: 6.4))
            light.line(to: NSPoint(x: 16.6, y: 6.4))
            light.line(to: NSPoint(x: 5.4, y: 12.6))
            light.close()
            light.fill()

            let stand = NSBezierPath()
            stand.move(to: NSPoint(x: 8, y: 18.3))
            stand.line(to: NSPoint(x: 14, y: 18.3))
            stand.lineWidth = 1.6
            stand.lineCapStyle = .round
            stand.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = appName
        return image
    }()
}
