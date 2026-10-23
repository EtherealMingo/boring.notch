//
//  ScreenshotManager.swift
//  boringNotch
//
//  Toolbox: capture screen (fullscreen / window / region), then hand the
//  image to the annotation editor. Uses ScreenCaptureKit.
//

import AppKit
import ScreenCaptureKit
import Defaults

@MainActor
final class ScreenshotManager: NSObject, ObservableObject {
    static let shared = ScreenshotManager()

    @Published var isCapturing = false
    @Published var lastCapturedImage: NSImage?

    private var regionOverlay: RegionSelectionOverlay?

    enum CaptureMode {
        case fullscreen
        case region
        case window
    }

    // MARK: - Entry points

    func capture(_ mode: CaptureMode) {
        switch mode {
        case .fullscreen:
            Task { await captureFullscreen() }
        case .region:
            beginRegionSelection()
        case .window:
            Task { await captureWindowUnderCursor() }
        }
    }

    // MARK: - Fullscreen

    private func captureFullscreen() async {
        guard let screen = screenUnderCursor() ?? NSScreen.main else { return }
        do {
            let image = try await captureScreenImage(screen: screen)
            presentEditor(with: image)
        } catch {
            NSLog("Fullscreen capture failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Region (custom)

    private func beginRegionSelection() {
        guard regionOverlay == nil else { return }
        isCapturing = true
        let overlay = RegionSelectionOverlay { [weak self] rect, screen in
            guard let self else { return }
            self.regionOverlay = nil
            self.isCapturing = false
            guard let rect, let screen else { return } // cancelled
            Task {
                do {
                    let full = try await self.captureScreenImage(screen: screen)
                    if let cropped = self.crop(full, to: rect, on: screen) {
                        self.presentEditor(with: cropped)
                    }
                } catch {
                    NSLog("Region capture failed: \(error.localizedDescription)")
                }
            }
        }
        regionOverlay = overlay
        overlay.show()
    }

    // MARK: - Window

    private func captureWindowUnderCursor() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let mouse = NSEvent.mouseLocation
            guard let target = content.windows.first(where: {
                $0.frame.contains(mouse) && $0.owningApplication?.bundleIdentifier != Bundle.main.bundleIdentifier
            }) ?? content.windows.first(where: {
                $0.owningApplication?.bundleIdentifier != Bundle.main.bundleIdentifier && $0.isOnScreen
            }) else { return }

            let filter = SCContentFilter(desktopIndependentWindow: target)
            let config = SCStreamConfiguration()
            config.width = Int(target.frame.width * 2)
            config.height = Int(target.frame.height * 2)
            config.showsCursor = false

            let cg = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            presentEditor(with: NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)))
        } catch {
            NSLog("Window capture failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    private func screenUnderCursor() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) }
    }

    private func captureScreenImage(screen: NSScreen) async throws -> NSImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first(where: { $0.displayID == screen.displayID })
                ?? content.displays.first else {
            throw NSError(domain: "ScreenshotManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "No display found"])
        }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        let scale = screen.backingScaleFactor
        config.width = Int(CGFloat(display.width) * scale)
        config.height = Int(CGFloat(display.height) * scale)
        config.showsCursor = false

        let cg = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    /// rect is in screen (point) coordinates with bottom-left origin, on `screen`.
    private func crop(_ image: NSImage, to rect: CGRect, on screen: NSScreen) -> NSImage? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let scale = screen.backingScaleFactor

        // Convert screen points (origin bottom-left of the global frame)
        // into image pixels (origin top-left of this display).
        let localX = rect.origin.x - screen.frame.origin.x
        let localYFromBottom = rect.origin.y - screen.frame.origin.y
        let topY = screen.frame.height - localYFromBottom - rect.height

        let pixelRect = CGRect(
            x: localX * scale,
            y: topY * scale,
            width: rect.width * scale,
            height: rect.height * scale
        ).integral

        guard let cropped = cg.cropping(to: pixelRect) else { return nil }
        return NSImage(cgImage: cropped, size: NSSize(width: cropped.width, height: cropped.height))
    }

    // MARK: - Editor handoff

    private func presentEditor(with image: NSImage) {
        lastCapturedImage = image
        AnnotationEditorWindowController.shared.present(with: image)
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
