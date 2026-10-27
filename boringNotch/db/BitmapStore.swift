//  BitmapStore.swift
//  boringNotch

import AppKit

enum BitmapStoreError: Error {
    case pngEncodingFailed
}

final class BitmapStore {
    static let shared = BitmapStore()

    private let directory: URL

    private init() {
        let fileManager = FileManager.default
        directory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("boringNotch", isDirectory: true)
            .appendingPathComponent("Bitmaps", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func absoluteURL(_ name: String) -> URL {
        directory.appendingPathComponent(name)
    }

    func save(_ image: CGImage) throws -> String {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw BitmapStoreError.pngEncodingFailed
        }
        return try save(data)
    }

    func save(_ data: Data) throws -> String {
        let name = UUID().uuidString + ".png"
        try data.write(to: absoluteURL(name), options: .atomic)
        return name
    }

    func removeAll() {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for file in files {
            try? fileManager.removeItem(at: file)
        }
    }

    func load(_ name: String) -> CGImage? {
        guard let data = try? Data(contentsOf: absoluteURL(name)) else { return nil }
        return NSBitmapImageRep(data: data)?.cgImage
    }

    /// Decodes directly at a small pixel size via ImageIO — avoids a full-size decode.
    func thumbnail(_ name: String, maxPixel: Int = 128) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(absoluteURL(name) as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    func delete(_ name: String) {
        try? FileManager.default.removeItem(at: absoluteURL(name))
    }

    func reconcileOrphans(referencedNames: Set<String>) {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.creationDateKey]
        ) else { return }
        let cutoff = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        for file in files where !referencedNames.contains(file.lastPathComponent) {
            let creation = (try? file.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
            if creation < cutoff {
                try? fileManager.removeItem(at: file)
            }
        }
    }
}
