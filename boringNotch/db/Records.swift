//  Records.swift
//  boringNotch

import Foundation
import GRDB

struct ClipboardItemRecord: Codable, FetchableRecord, PersistableRecord {
    var id: Int64?
    var contentType: String
    var contentText: String?
    var contentBlob: Data?
    var contentHash: String?
    var sourceApp: String?
    var isPinned: Bool
    var isSensitive: Bool
    var createdAt: Date

    static let databaseTableName = "clipboard_item"
    static let databaseDateDecodingStrategy: DatabaseDateDecodingStrategy = .timeIntervalSince1970
    static let databaseDateEncodingStrategy: DatabaseDateEncodingStrategy = .timeIntervalSince1970

    enum CodingKeys: String, CodingKey {
        case id
        case contentType = "content_type"
        case contentText = "content_text"
        case contentBlob = "content_blob"
        case contentHash = "content_hash"
        case sourceApp = "source_app"
        case isPinned = "is_pinned"
        case isSensitive = "is_sensitive"
        case createdAt = "created_at"
    }

    enum Columns {
        static let id = Column("id")
        static let contentType = Column("content_type")
        static let contentText = Column("content_text")
        static let contentBlob = Column("content_blob")
        static let contentHash = Column("content_hash")
        static let sourceApp = Column("source_app")
        static let isPinned = Column("is_pinned")
        static let isSensitive = Column("is_sensitive")
        static let createdAt = Column("created_at")
    }

    static func search(_ query: String, in db: Database) throws -> [ClipboardItemRecord] {
        let tokens = query
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }
        guard !tokens.isEmpty else { return [] }
        let sql = """
            SELECT clipboard_item.*
            FROM clipboard_item
            JOIN clipboard_fts ON clipboard_fts.rowid = clipboard_item.id
            WHERE clipboard_fts MATCH ?
            ORDER BY clipboard_item.is_pinned DESC, clipboard_item.created_at DESC
            """
        return try ClipboardItemRecord.fetchAll(db, sql: sql, arguments: [tokens.joined(separator: " ")])
    }

    static func recent(limit: Int, in db: Database) throws -> [ClipboardItemRecord] {
        try ClipboardItemRecord
            .order(Columns.isPinned.desc, Columns.createdAt.desc)
            .limit(limit)
            .fetchAll(db)
    }
}

struct IgnoredApp: Codable, FetchableRecord, PersistableRecord {
    var bundleId: String
    var addedAt: Date

    static let databaseTableName = "ignored_app"
    static let databaseDateDecodingStrategy: DatabaseDateDecodingStrategy = .timeIntervalSince1970
    static let databaseDateEncodingStrategy: DatabaseDateEncodingStrategy = .timeIntervalSince1970

    enum CodingKeys: String, CodingKey {
        case bundleId = "bundle_id"
        case addedAt = "added_at"
    }

    enum Columns {
        static let bundleId = Column("bundle_id")
        static let addedAt = Column("added_at")
    }
}
