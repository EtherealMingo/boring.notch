//
//  RegionSelectionOverlay.swift
//  boringNotch
//
//  Toolbox: fullscreen dimmed overlay for custom region selection.
//  Drag to select, ESC to cancel.
//

import AppKit

final class RegionSelectionOverlay {
    private var windows: [NSWindow] = []
    private var completion: (CGRect?, NSScreen?) -> Void

    init(completion: @escaping (CGRect?, NSScreen?) -> Void) {
        self.completion = completion
    }

    func show() {
        for screen in NSScreen.screens {
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)) - 1)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.ignoresMouseEvents = false
            window.acceptsMouseMovedEvents = true
            window.hasShadow = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

            let view = RegionSelectionView(frame: screen.frame, screen: screen) { [weak self] rect in
                self?.finish(rect: rect, screen: screen)
            }
            window.contentView = view
            window.makeKeyAndOrderFront(nil)
            windows.append(window)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func finish(rect: CGRect?, screen: NSScreen) {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        completion(rect, screen)
    }
}

private final class RegionSelectionView: NSView {
    private var startPoint: NSPoint?
    private var currentPoint: NSPoint?
    private let screen: NSScreen
    private let onFinish: (CGRect?) -> Void
    private var sizeLabel: NSTextField?

    init(frame: NSRect, screen: NSScreen, onFinish: @escaping (CGRect?) -> Void) {
        self.screen = screen
        self.onFinish = onFinish
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.25).setFill()
        dirtyRect.fill()

        guard let selection = selectionRect() else { return }

        // Clear the selected hole
        NSColor.clear.setFill()
        selection.fill(using: .copy)

        // Border
        NSColor.white.withAlphaComponent(0.9).setStroke()
        let path = NSBezierPath(rect: selection)
        path.lineWidth = 1.5
        path.stroke()
    }

    private func selectionRect() -> CGRect? {
        guard let start = startPoint, let current = currentPoint else { return nil }
        return CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentPoint = startPoint
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        updateSizeLabel()
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        guard let local = selectionRect(), local.width > 4, local.height > 4 else {
            cleanup()
            return
        }
        // Convert view coords (bottom-left origin within this screen's window)
        // to global screen coords.
        let global = CGRect(
            x: screen.frame.origin.x + local.origin.x,
            y: screen.frame.origin.y + local.origin.y,
            width: local.width,
            height: local.height
        )
        onFinish(global)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC
            cleanup()
            onFinish(nil)
        }
    }

    private func cleanup() {
        startPoint = nil
        currentPoint = nil
        sizeLabel?.removeFromSuperview()
        sizeLabel = nil
        needsDisplay = true
    }

    private func updateSizeLabel() {
        guard let rect = selectionRect() else { return }
        if sizeLabel == nil {
            let label = NSTextField(labelWithString: "")
            label.textColor = .white
            label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            label.backgroundColor = NSColor.black.withAlphaComponent(0.7)
            label.isBezeled = false
            label.drawsBackground = true
            addSubview(label)
            sizeLabel = label
        }
        sizeLabel?.stringValue = " \(Int(rect.width)) × \(Int(rect.height)) "
        sizeLabel?.sizeToFit()
        sizeLabel?.frame.origin = NSPoint(
            x: rect.maxX + 8,
            y: max(8, rect.minY - 28)
        )
    }
}
