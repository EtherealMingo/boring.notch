//
//  ClipboardManager.swift
//  boringNotch
//
//  Toolbox: clipboard history (text / link / image), favorites,
//  persistence and paste-back into the previously active app.
//

import AppKit
import Combine
import Defaults

enum ClipboardItemType: String, Codable {
    case text, link, image
}

struct ClipboardItem: Identifiable, Codable, Equatable {
    let id: UUID
    var type: ClipboardItemType
    var text: String?           // text & link content, or OCR-ish label for image
    var imageFileName: String?  // PNG file in the clipboard images directory
    var timestamp: Date
    var isFavorite: Bool
    var sourceAppName: String?
    var sourceAppBundleID: String?

    static func == (lhs: ClipboardItem, rhs: ClipboardItem) -> Bool { lhs.id == rhs.id }
}

@MainActor
final class ClipboardManager: ObservableObject {
    static let shared = ClipboardManager()

    @Published private(set) var items: [ClipboardItem] = []

    private var timer: Timer?
    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    private var suppressNextChange = false

    /// The app that was frontmost before the notch took focus — paste target.
    private(set) var previousApp: NSRunningApplication?
    private var activationObserver: Any?

    // MARK: Storage locations

    private var storageDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("boringNotch/ClipboardHistory", isDirectory: true)
    }
    private var indexFileURL: URL { storageDirectory.appendingPathComponent("history.json") }

    private init() {
        load()
        previousApp = NSWorkspace.shared.frontmostApplication
            .flatMap { $0.bundleIdentifier == Bundle.main.bundleIdentifier ? nil : $0 }
    }

    // MARK: - Lifecycle

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
            Task { @MainActor in self?.previousApp = app }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }
    }

    // MARK: - Polling

    private func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount

        if suppressNextChange {
            suppressNextChange = false
            return
        }

        let sourceApp = previousApp

        // Image first (screenshots often carry both image and text)
        if let image = pb.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage,
           pb.types?.contains(.tiff) == true || pb.types?.contains(.png) == true {
            addImageItem(image, sourceApp: sourceApp)
            return
        }

        if let urlString = pb.string(forType: .URL) ?? (pb.string(forType: .string).flatMap { s in
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return (t.hasPrefix("http://") || t.hasPrefix("https://")) && !t.contains(" ") ? t : nil
        }) {
            addItem(type: .link, text: urlString, sourceApp: sourceApp)
            return
        }

        if let string = pb.string(forType: .string), !string.isEmpty {
            addItem(type: .text, text: string, sourceApp: sourceApp)
        }
    }

    // MARK: - Add

    private func addItem(type: ClipboardItemType, text: String, sourceApp: NSRunningApplication?) {
        // De-duplicate: move existing to top
        if let existing = items.firstIndex(where: { $0.type == type && $0.text == text }) {
            var item = items.remove(at: existing)
            item.timestamp = Date()
            items.insert(item, at: 0)
            save()
            return
        }
        let item = ClipboardItem(
            id: UUID(), type: type, text: text, imageFileName: nil,
            timestamp: Date(), isFavorite: false,
            sourceAppName: sourceApp?.localizedName,
            sourceAppBundleID: sourceApp?.bundleIdentifier
        )
        insert(item)
    }

    private func addImageItem(_ image: NSImage, sourceApp: NSRunningApplication?) {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }

        let hash = png.sha1Prefix
        if let existing = items.firstIndex(where: { $0.type == .image && $0.text == hash }) {
            var item = items.remove(at: existing)
            item.timestamp = Date()
            items.insert(item, at: 0)
            save()
            return
        }

        let fileName = "\(UUID().uuidString).png"
        do {
            try FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
            try png.write(to: storageDirectory.appendingPathComponent(fileName))
        } catch {
            NSLog("Clipboard image save failed: \(error.localizedDescription)")
            return
        }

        let item = ClipboardItem(
            id: UUID(), type: .image, text: hash, imageFileName: fileName,
            timestamp: Date(), isFavorite: false,
            sourceAppName: sourceApp?.localizedName,
            sourceAppBundleID: sourceApp?.bundleIdentifier
        )
        insert(item)
    }

    private func insert(_ item: ClipboardItem) {
        items.insert(item, at: 0)
        let limit = Defaults[.clipboardHistoryLimit]
        // Trim non-favorites beyond limit
        var kept: [ClipboardItem] = []
        var nonFavoriteCount = 0
        for i in items {
            if i.isFavorite || nonFavoriteCount < limit {
                kept.append(i)
                if !i.isFavorite { nonFavoriteCount += 1 }
            } else {
                deleteImageFile(for: i)
            }
        }
        items = kept
        save()
    }

    // MARK: - Public actions

    func toggleFavorite(_ item: ClipboardItem) {
        guard let idx = items.firstIndex(of: item) else { return }
        items[idx].isFavorite.toggle()
        save()
    }

    func delete(_ item: ClipboardItem) {
        items.removeAll { $0 == item }
        deleteImageFile(for: item)
        save()
    }

    func clearHistory(keepFavorites: Bool = true) {
        let removed = keepFavorites ? items.filter { !$0.isFavorite } : items
        removed.forEach { deleteImageFile(for: $0) }
        items = keepFavorites ? items.filter { $0.isFavorite } : []
        save()
    }

    func copyToPasteboard(_ item: ClipboardItem) {
        suppressNextChange = true
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.type {
        case .text, .link:
            if let text = item.text {
                pb.setString(text, forType: .string)
            }
        case .image:
            if let image = imageFor(item) {
                pb.writeObjects([image])
            }
        }
        lastChangeCount = pb.changeCount
        suppressNextChange = false
    }

    /// Copy item, close the notch and paste into the previously active app.
    func pasteIntoPreviousApp(_ item: ClipboardItem) {
        copyToPasteboard(item)
        NotificationCenter.default.post(name: .closeNotch, object: nil)

        Task {
            try? await Task.sleep(for: .milliseconds(250))
            if let app = previousApp {
                app.activate(options: [])
                try? await Task.sleep(for: .milliseconds(200))
            }
            simulatePaste()
        }
    }

    func imageFor(_ item: ClipboardItem) -> NSImage? {
        guard let name = item.imageFileName else { return nil }
        return NSImage(contentsOf: storageDirectory.appendingPathComponent(name))
    }

    // MARK: - Persistence

    private func save() {
        do {
            try FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(items)
            try data.write(to: indexFileURL, options: .atomic)
        } catch {
            NSLog("Clipboard history save failed: \(error.localizedDescription)")
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexFileURL),
              let decoded = try? JSONDecoder().decode([ClipboardItem].self, from: data) else { return }
        items = decoded
    }

    private func deleteImageFile(for item: ClipboardItem) {
        guard let name = item.imageFileName else { return }
        try? FileManager.default.removeItem(at: storageDirectory.appendingPathComponent(name))
    }

    // MARK: - Paste simulation

    private func simulatePaste() {
        guard TranslateService.shared.ensureAccessibility(prompt: false) else { return }
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true) // V
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}

extension Notification.Name {
    static let closeNotch = Notification.Name("closeNotch")
}

private extension Data {
    var sha1Prefix: String {
        // Cheap content fingerprint for image de-duplication
        var hash: UInt64 = 5381
        for byte in self.prefix(64 * 1024) {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        return String(format: "%016llx", hash)
    }
}
