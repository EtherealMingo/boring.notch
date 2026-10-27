//
//  ClipboardManager.swift
//  boringNotch
//
//  Toolbox: clipboard history (text / rtf / image / file path / url),
//  GRDB persistence, paste-back into the previously active app.
//

import AppKit
import Combine
import CryptoKit
import Defaults
import GRDB

enum ClipboardItemType: String, Codable {
    case text, rtf, image
    case filePath = "file_path"
    case url
}

struct ClipboardItem: Identifiable, Equatable, Sendable {
    let id: Int64
    var type: ClipboardItemType
    var text: String?           // text / url / file paths / bitmap file name for image
    var blob: Data?             // rtf payload
    var timestamp: Date
    var isPinned: Bool
    var sourceAppBundleID: String?

    static func == (lhs: ClipboardItem, rhs: ClipboardItem) -> Bool { lhs.id == rhs.id }
}

@MainActor
final class ClipboardManager: ObservableObject {
    static let shared = ClipboardManager()

    nonisolated private static let historyLimit = 500
    nonisolated private static let maxPayloadBytes = 50 * 1024 * 1024
    nonisolated private static let dedupeWindow: TimeInterval = 10
    nonisolated private static let imageMaxAge: TimeInterval = 7 * 24 * 60 * 60
    nonisolated private static let expireAge: TimeInterval = 24 * 60 * 60

    @Published private(set) var items: [ClipboardItem] = []
    @Published private(set) var searchResults: [ClipboardItem]?
    @Published private(set) var bannerMessage: String?
    @Published private(set) var databaseRebuiltNotice: String?

    private var timer: Timer?
    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    private var suppressNextChange = false
    private var bannerTask: Task<Void, Never>?

    // NSCache is thread-safe; prewarming happens off the main actor.
    nonisolated(unsafe) private let thumbnailCache = NSCache<NSNumber, NSImage>()
    private var appNameCache: [String: String] = [:]

    /// The app that was frontmost before the notch took focus — paste target.
    private(set) var previousApp: NSRunningApplication?
    private var activationObserver: Any?

    // MARK: Legacy storage (one-time migration source)

    private var legacyStorageDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("boringNotch/ClipboardHistory", isDirectory: true)
    }
    private var legacyIndexFileURL: URL { legacyStorageDirectory.appendingPathComponent("history.json") }

    private init() {
        previousApp = NSWorkspace.shared.frontmostApplication
            .flatMap { $0.bundleIdentifier == Bundle.main.bundleIdentifier ? nil : $0 }
        if DatabaseManager.shared.didRecoverFromCorruption {
            databaseRebuiltNotice = "数据库已重建，历史已备份"
        }
        reloadItems()
        migrateLegacyHistoryIfNeeded()
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
        runDailyCleanupIfNeeded()
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

    private enum Captured: Sendable {
        case image(Data)
        case filePaths([String])
        case rtf(Data, String)
        case url(String)
        case text(String)
    }

    private func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount

        if suppressNextChange {
            suppressNextChange = false
            return
        }

        let sourceApp = previousApp
        let captured = capture(from: pb)
        guard let captured else { return }

        Task.detached { [weak self] in
            self?.persist(captured, sourceAppBundleID: sourceApp?.bundleIdentifier)
        }
    }

    private func capture(from pb: NSPasteboard) -> Captured? {
        // Image first (screenshots often carry both image and text)
        if (pb.types?.contains(.tiff) == true || pb.types?.contains(.png) == true),
           let image = pb.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage,
           let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
           let png = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) {
            return .image(png)
        }

        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            return .filePaths(urls.map(\.path))
        }

        if let rtf = pb.data(forType: .rtf) {
            let plain = pb.string(forType: .string) ?? ""
            return .rtf(rtf, plain)
        }

        if let urlString = pb.string(forType: .URL) ?? (pb.string(forType: .string).flatMap { s in
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return (t.hasPrefix("http://") || t.hasPrefix("https://")) && !t.contains(" ") ? t : nil
        }) {
            return .url(urlString)
        }

        if let string = pb.string(forType: .string), !string.isEmpty {
            return .text(string)
        }

        return nil
    }

    // MARK: - Persistence

    nonisolated private func persist(_ captured: Captured, sourceAppBundleID: String?) {
        let queue = DatabaseManager.shared.dbQueue
        do {
            try queue.write { db in
                if let bundleID = sourceAppBundleID,
                   let ignored = try Bool.fetchOne(
                       db,
                       sql: "SELECT EXISTS(SELECT 1 FROM ignored_app WHERE bundle_id = ?)",
                       arguments: [bundleID]
                   ), ignored {
                    return
                }

                let now = Date()
                var contentType: String
                var contentText: String?
                var contentBlob: Data?
                var hashData: Data
                var bitmapName: String?

                switch captured {
                case .image(let png):
                    guard png.count <= Self.maxPayloadBytes else { return }
                    contentType = ClipboardItemType.image.rawValue
                    hashData = png
                    bitmapName = try BitmapStore.shared.save(png)
                    contentText = bitmapName
                case .filePaths(let paths):
                    let text = paths.joined(separator: "\n")
                    guard let data = text.data(using: .utf8), data.count <= Self.maxPayloadBytes else { return }
                    contentType = ClipboardItemType.filePath.rawValue
                    contentText = text
                    hashData = data
                case .rtf(let rtf, let plain):
                    guard rtf.count <= Self.maxPayloadBytes else { return }
                    contentType = ClipboardItemType.rtf.rawValue
                    contentText = plain
                    contentBlob = rtf
                    hashData = rtf
                case .url(let url):
                    guard let data = url.data(using: .utf8), data.count <= Self.maxPayloadBytes else { return }
                    contentType = ClipboardItemType.url.rawValue
                    contentText = url
                    hashData = data
                case .text(let text):
                    guard let data = text.data(using: .utf8), data.count <= Self.maxPayloadBytes else { return }
                    contentType = ClipboardItemType.text.rawValue
                    contentText = text
                    hashData = data
                }

                let hash = SHA256.hash(data: hashData).map { String(format: "%02x", $0) }.joined()

                // De-duplicate inside a short window: bump the existing row instead.
                if let existingID = try Int64.fetchOne(
                    db,
                    sql: "SELECT id FROM clipboard_item WHERE content_hash = ? AND created_at > ? ORDER BY created_at DESC LIMIT 1",
                    arguments: [hash, now.addingTimeInterval(-Self.dedupeWindow).timeIntervalSince1970]
                ) {
                    if let bitmapName { BitmapStore.shared.delete(bitmapName) }
                    try db.execute(
                        sql: "UPDATE clipboard_item SET created_at = ? WHERE id = ?",
                        arguments: [now.timeIntervalSince1970, existingID]
                    )
                    return
                }

                var record = ClipboardItemRecord(
                    id: nil,
                    contentType: contentType,
                    contentText: contentText,
                    contentBlob: contentBlob,
                    contentHash: hash,
                    sourceApp: sourceAppBundleID,
                    isPinned: false,
                    isSensitive: false,
                    createdAt: now
                )
                try record.insert(db)
                try Self.trimToHistoryLimit(in: db)
            }
        } catch {
            NSLog("Clipboard persist failed: \(error.localizedDescription)")
        }
        Task { @MainActor [weak self] in self?.reloadItems() }
    }

    nonisolated private static func trimToHistoryLimit(in db: Database) throws {
        let nonPinnedCount = try Int.fetchOne(
            db, sql: "SELECT COUNT(*) FROM clipboard_item WHERE is_pinned = 0"
        ) ?? 0
        let overflow = nonPinnedCount - historyLimit
        guard overflow > 0 else { return }
        let stale = try Row.fetchAll(
            db,
            sql: "SELECT id, content_type, content_text FROM clipboard_item WHERE is_pinned = 0 ORDER BY created_at ASC LIMIT ?",
            arguments: [overflow]
        )
        for row in stale {
            let id: Int64 = row["id"]
            let type: String? = row["content_type"]
            let text: String? = row["content_text"]
            try db.execute(sql: "DELETE FROM clipboard_item WHERE id = ?", arguments: [id])
            if type == ClipboardItemType.image.rawValue, let text {
                BitmapStore.shared.delete(text)
            }
        }
    }

    private func reloadItems() {
        Task.detached { [weak self] in
            let records = (try? await DatabaseManager.shared.dbQueue.read { db in
                try ClipboardItemRecord.recent(limit: 600, in: db)
            }) ?? []
            let mapped = records.compactMap(Self.item(from:))
            self?.prewarmThumbnails(for: Array(mapped.prefix(40)))
            await MainActor.run { self?.items = mapped }
        }
    }

    nonisolated private func prewarmThumbnails(for items: [ClipboardItem]) {
        for item in items where item.type == .image {
            let key = NSNumber(value: item.id)
            guard thumbnailCache.object(forKey: key) == nil, let name = item.text else { continue }
            if let image = Self.makeThumbnail(name: name) {
                thumbnailCache.setObject(image, forKey: key)
            }
        }
    }

    nonisolated private static func makeThumbnail(name: String) -> NSImage? {
        guard let cgImage = BitmapStore.shared.thumbnail(name) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    /// Small cached thumbnail for list rows; full decode stays in imageFor (OCR/copy).
    func thumbnail(for item: ClipboardItem) -> NSImage? {
        guard item.type == .image else { return nil }
        let key = NSNumber(value: item.id)
        if let cached = thumbnailCache.object(forKey: key) { return cached }
        guard let name = item.text, let image = Self.makeThumbnail(name: name) else { return nil }
        thumbnailCache.setObject(image, forKey: key)
        return image
    }

    /// Memoized LaunchServices lookup — calling this per row render stalls the UI.
    func sourceAppName(for bundleID: String?) -> String? {
        guard let bundleID, !bundleID.isEmpty else { return nil }
        if let cached = appNameCache[bundleID] { return cached }
        var name = bundleID
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            name = FileManager.default.displayName(atPath: url.path)
        }
        appNameCache[bundleID] = name
        return name
    }

    nonisolated private static func item(from record: ClipboardItemRecord) -> ClipboardItem? {
        guard let id = record.id, let type = ClipboardItemType(rawValue: record.contentType) else { return nil }
        return ClipboardItem(
            id: id,
            type: type,
            text: record.contentText,
            blob: record.contentBlob,
            timestamp: record.createdAt,
            isPinned: record.isPinned,
            sourceAppBundleID: record.sourceApp
        )
    }

    // MARK: - Search

    func search(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = nil
            return
        }
        Task.detached { [weak self] in
            let records = (try? await DatabaseManager.shared.dbQueue.read { db in
                try ClipboardItemRecord.search(trimmed, in: db)
            }) ?? []
            let mapped = records.compactMap(Self.item(from:))
            await MainActor.run { self?.searchResults = mapped }
        }
    }

    // MARK: - Public actions

    func togglePin(_ item: ClipboardItem) {
        Task.detached { [weak self] in
            try? await DatabaseManager.shared.dbQueue.write { db in
                try db.execute(
                    sql: "UPDATE clipboard_item SET is_pinned = ? WHERE id = ?",
                    arguments: [!item.isPinned, item.id]
                )
            }
            await MainActor.run { self?.reloadItems() }
        }
    }

    func delete(_ item: ClipboardItem) {
        thumbnailCache.removeObject(forKey: NSNumber(value: item.id))
        Task.detached { [weak self] in
            try? await DatabaseManager.shared.dbQueue.write { db in
                try db.execute(sql: "DELETE FROM clipboard_item WHERE id = ?", arguments: [item.id])
            }
            if item.type == .image, let name = item.text {
                BitmapStore.shared.delete(name)
            }
            await MainActor.run { self?.reloadItems() }
        }
    }

    /// CLIP-08: mark sensitive = remove immediately, nothing is kept.
    func markSensitiveAndDelete(_ item: ClipboardItem) {
        delete(item)
    }

    func clearHistory(keepPinned: Bool = true) {
        thumbnailCache.removeAllObjects()
        Task.detached { [weak self] in
            let names = (try? await DatabaseManager.shared.dbQueue.write { db -> [String] in
                let rows = try Row.fetchAll(
                    db,
                    sql: keepPinned
                        ? "SELECT content_text FROM clipboard_item WHERE content_type = 'image' AND is_pinned = 0"
                        : "SELECT content_text FROM clipboard_item WHERE content_type = 'image'"
                )
                if keepPinned {
                    try db.execute(sql: "DELETE FROM clipboard_item WHERE is_pinned = 0")
                } else {
                    try db.execute(sql: "DELETE FROM clipboard_item")
                }
                return rows.compactMap { $0["content_text"] as String? }
            }) ?? []
            for name in names { BitmapStore.shared.delete(name) }
            await MainActor.run {
                self?.reloadItems()
                self?.showBanner("已清空历史")
            }
        }
    }

    /// Onboarding escape hatch: wipe rows and every bitmap on disk.
    func clearAllHistory() {
        thumbnailCache.removeAllObjects()
        Task.detached { [weak self] in
            try? await DatabaseManager.shared.dbQueue.write { db in
                try db.execute(sql: "DELETE FROM clipboard_item")
            }
            BitmapStore.shared.removeAll()
            await MainActor.run { self?.reloadItems() }
        }
    }

    func copyToPasteboard(_ item: ClipboardItem) {
        suppressNextChange = true
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.type {
        case .text, .url:
            if let text = item.text {
                pb.setString(text, forType: .string)
            }
        case .rtf:
            if let blob = item.blob {
                pb.setData(blob, forType: .rtf)
            }
            if let text = item.text {
                pb.setString(text, forType: .string)
            }
        case .filePath:
            let urls = (item.text ?? "")
                .components(separatedBy: "\n")
                .filter { !$0.isEmpty }
                .map { NSURL(fileURLWithPath: $0) }
            if !urls.isEmpty {
                pb.writeObjects(urls)
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
        Task {
            let trusted = await XPCHelperClient.shared.isAccessibilityAuthorized()
            guard trusted else {
                showBanner("已复制，请手动 ⌘V")
                return
            }
            NotificationCenter.default.post(name: .closeNotch, object: nil)
            try? await Task.sleep(for: .milliseconds(250))
            if let app = previousApp {
                app.activate(options: [])
                try? await Task.sleep(for: .milliseconds(200))
            }
            simulatePaste()
        }
    }

    func imageFor(_ item: ClipboardItem) -> NSImage? {
        guard item.type == .image, let name = item.text,
              let cgImage = BitmapStore.shared.load(name) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    // MARK: - Banner

    func showBanner(_ message: String) {
        bannerTask?.cancel()
        bannerMessage = message
        bannerTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            bannerMessage = nil
        }
    }

    func acknowledgeDatabaseRebuiltNotice() {
        databaseRebuiltNotice = nil
    }

    // MARK: - Daily cleanup

    private func runDailyCleanupIfNeeded() {
        Task.detached {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let today = formatter.string(from: Date())
            guard DatabaseManager.shared.setting(forKey: "last_cleanup_date") != today else { return }

            let queue = DatabaseManager.shared.dbQueue
            let expireAll = Defaults[.clipboardExpireAfter24h]
            do {
                let removedNames = try await queue.write { db -> [String] in
                    var removed: [String] = []
                    let imageCutoff = Date().addingTimeInterval(-Self.imageMaxAge).timeIntervalSince1970
                    let expiredImages = try Row.fetchAll(
                        db,
                        sql: "SELECT id, content_text FROM clipboard_item WHERE content_type = 'image' AND is_pinned = 0 AND created_at < ?",
                        arguments: [imageCutoff]
                    )
                    for row in expiredImages {
                        try db.execute(sql: "DELETE FROM clipboard_item WHERE id = ?", arguments: [row["id"] as Int64])
                        if let name: String = row["content_text"] { removed.append(name) }
                    }

                    if expireAll {
                        let cutoff = Date().addingTimeInterval(-Self.expireAge).timeIntervalSince1970
                        let expired = try Row.fetchAll(
                            db,
                            sql: "SELECT id, content_type, content_text FROM clipboard_item WHERE is_pinned = 0 AND created_at < ?",
                            arguments: [cutoff]
                        )
                        for row in expired {
                            try db.execute(sql: "DELETE FROM clipboard_item WHERE id = ?", arguments: [row["id"] as Int64])
                            if (row["content_type"] as String?) == ClipboardItemType.image.rawValue,
                               let name: String = row["content_text"] {
                                removed.append(name)
                            }
                        }
                    }

                    try Self.trimToHistoryLimit(in: db)
                    return removed
                }
                for name in removedNames {
                    BitmapStore.shared.delete(name)
                }
                let referenced = try await queue.read { db in
                    Set(try String.fetchAll(
                        db,
                        sql: "SELECT content_text FROM clipboard_item WHERE content_type = 'image' AND content_text IS NOT NULL"
                    ))
                }
                BitmapStore.shared.reconcileOrphans(referencedNames: referenced)
            } catch {
                NSLog("Clipboard daily cleanup failed: \(error.localizedDescription)")
            }
            DatabaseManager.shared.setSetting(today, forKey: "last_cleanup_date")
        }
    }

    // MARK: - Legacy history.json migration

    private struct LegacyClipboardItem: Codable {
        let id: UUID
        var type: String
        var text: String?
        var imageFileName: String?
        var timestamp: Date
        var isFavorite: Bool
        var sourceAppName: String?
        var sourceAppBundleID: String?
    }

    private func migrateLegacyHistoryIfNeeded() {
        let fileManager = FileManager.default
        let indexURL = legacyIndexFileURL
        let legacyDirectory = legacyStorageDirectory
        guard fileManager.fileExists(atPath: indexURL.path),
              let data = try? Data(contentsOf: indexURL),
              let legacy = try? JSONDecoder().decode([LegacyClipboardItem].self, from: data) else { return }

        Task.detached { [weak self] in
            let queue = DatabaseManager.shared.dbQueue
            do {
                try await queue.write { db in
                    for old in legacy.reversed() {
                        let contentType: String
                        var contentText = old.text
                        var hashData = Data()
                        switch old.type {
                        case "link":
                            contentType = ClipboardItemType.url.rawValue
                        case "image":
                            contentType = ClipboardItemType.image.rawValue
                            if let fileName = old.imageFileName {
                                let source = legacyDirectory.appendingPathComponent(fileName)
                                let destination = BitmapStore.shared.absoluteURL(fileName)
                                if fileManager.fileExists(atPath: source.path),
                                   !fileManager.fileExists(atPath: destination.path) {
                                    try? fileManager.copyItem(at: source, to: destination)
                                }
                                if let png = try? Data(contentsOf: destination) {
                                    hashData = png
                                }
                                contentText = fileName
                            }
                        default:
                            contentType = ClipboardItemType.text.rawValue
                        }
                        if hashData.isEmpty, let text = contentText {
                            hashData = text.data(using: .utf8) ?? Data()
                        }
                        guard !hashData.isEmpty else { continue }
                        let hash = SHA256.hash(data: hashData).map { String(format: "%02x", $0) }.joined()
                        var record = ClipboardItemRecord(
                            id: nil,
                            contentType: contentType,
                            contentText: contentText,
                            contentBlob: nil,
                            contentHash: hash,
                            sourceApp: old.sourceAppBundleID,
                            isPinned: old.isFavorite,
                            isSensitive: false,
                            createdAt: old.timestamp
                        )
                        try record.insert(db)
                    }
                    try Self.trimToHistoryLimit(in: db)
                }
                try? fileManager.moveItem(
                    at: indexURL,
                    to: legacyDirectory.appendingPathComponent("history.json.migrated")
                )
            } catch {
                NSLog("Legacy clipboard migration failed: \(error.localizedDescription)")
            }
            await MainActor.run { self?.reloadItems() }
        }
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
