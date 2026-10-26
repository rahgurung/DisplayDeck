import AppKit
import SwiftUI

/// Small on-screen indicator shown when keys change brightness or volume.
final class HUD {
    static let shared = HUD()

    private let panel: NSPanel
    private let model = Model()
    private var hideWorkItem: DispatchWorkItem?

    @Observable final class Model {
        var symbol = "sun.max.fill"
        var value: Double? = 0.5
        var caption: String?
    }

    private init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 220, height: 56),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: HUDView(model: model))
    }

    /// - Parameter value: the level shown in the bar; nil for no bar, e.g. when a shortcut switched an input.
    /// - Parameter caption: shown above the bar, e.g. "All displays" when a key changed more than one display, or on its
    ///   own without a value.
    func show(symbol: String, value: Double?, caption: String? = nil) {
        model.symbol = symbol
        model.value = value
        model.caption = caption
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.minY + 80))
        }
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        hideWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                self?.panel.animator().alphaValue = 0
            }
        }
        hideWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: item)
    }
}

private struct HUDView: View {
    let model: HUD.Model

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: model.symbol)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                if let value = model.value {
                    if let caption = model.caption {
                        Text(caption)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: value)
                        .progressViewStyle(.linear)
                } else if let caption = model.caption {
                    Text(caption)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            }
        }
        .padding(.horizontal, 18)
        .frame(width: 220, height: 56, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}
