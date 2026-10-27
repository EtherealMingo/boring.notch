//
//  PinnedShotWindow.swift
//  boringNotch
//
//  Toolbox: pin a screenshot in a floating always-on-top window (Snipaste style).
//

import AppKit

final class PinnedShotWindow: NSPanel {
    private static var pinned: [PinnedShotWindow] = []
    private static var allVisible = true

    static func pin(image: NSImage, at origin: NSPoint? = nil) {
        let maxSize = NSSize(width: 600, height: 600)
        let scale = min(maxSize.width / image.size.width, maxSize.height / image.size.height, 1.0)
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)

        let window = PinnedShotWindow(
            contentRect: NSRect(origin: origin ?? NSEvent.mouseLocation, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true

        window.contentView = PinnedImageView(image: image) {
            PinnedShotWindow.pinned.removeAll { $0 === window }
            window.close()
        }

        window.orderFrontRegardless()
        pinned.append(window)
    }

    /// Pin whatever image currently sits on the general pasteboard; no-op when
    /// the clipboard holds no image.
    static func pinFromClipboard() {
        guard let image = NSImage(pasteboard: .general) else { return }
        pin(image: image)
    }

    static func toggleAllVisibility() {
        allVisible.toggle()
        for window in pinned {
            if allVisible {
                window.orderFrontRegardless()
            } else {
                window.orderOut(nil)
            }
        }
    }
}

private final class PinnedImageView: NSView {
    private let image: NSImage
    private let onClose: () -> Void
    private var closeButton: NSButton!

    init(image: NSImage, onClose: @escaping () -> Void) {
        self.image = image
        self.onClose = onClose
        super.init(frame: NSRect(origin: .zero, size: image.size))
        wantsLayer = true
        layer?.contents = image
        layer?.contentsGravity = .resizeAspect
        layer?.cornerRadius = 6
        layer?.masksToBounds = true

        closeButton = NSButton(title: "✕", target: self, action: #selector(closeTapped))
        closeButton.isBordered = false
        closeButton.font = .systemFont(ofSize: 11, weight: .bold)
        closeButton.contentTintColor = .white
        closeButton.wantsLayer = true
        closeButton.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.6).cgColor
        closeButton.layer?.cornerRadius = 8
        closeButton.frame = NSRect(x: 4, y: frame.height - 20, width: 16, height: 16)
        closeButton.alphaValue = 0
        addSubview(closeButton)

        let tracking = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(tracking)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func mouseEntered(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            closeButton.animator().alphaValue = 1
        }
    }

    override func mouseExited(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            closeButton.animator().alphaValue = 0
        }
    }

    @objc private func closeTapped() { onClose() }
}
