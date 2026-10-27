//  DatabaseManager.swift
//  boringNotch

import Foundation
import GRDB

final class DatabaseManager {
    static let shared = DatabaseManager()

    private(set) var didRecoverFromCorruption = false

    private var queue: DatabaseQueue

    var dbQueue: DatabaseQueue { queue }

    private init() {
        let fileManager = FileManager.default
        let directory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("boringNotch", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let databaseURL = directory.appendingPathComponent("lingdongdao.db")

        var configuration = Configuration()
        configuration.journalMode = .wal

        do {
            let queue = try DatabaseQueue(path: databaseURL.path, configuration: configuration)
            self.queue = queue
            try runMigrations()
        } catch {
            didRecoverFromCorruption = true
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            let corruptURL = directory.appendingPathComponent("history-corrupt-\(formatter.string(from: Date())).db")
            if fileManager.fileExists(atPath: databaseURL.path) {
                try? fileManager.moveItem(at: databaseURL, to: corruptURL)
            }
            try? fileManager.removeItem(atPath: databaseURL.path + "-wal")
            try? fileManager.removeItem(atPath: databaseURL.path + "-shm")

            if let rebuilt = try? DatabaseQueue(path: databaseURL.path, configuration: configuration) {
                self.queue = rebuilt
                try? runMigrations()
            } else {
                self.queue = try! DatabaseQueue()
            }
        }
    }

    func runMigrations() throws {
        var migrator = DatabaseMigrator()
        DatabaseMigrations.register(&migrator)
        try migrator.migrate(queue)
    }

    func setting(forKey key: String) -> String? {
        try? queue.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM kv_setting WHERE key = ?", arguments: [key])
        } ?? nil
    }

    func setSetting(_ value: String?, forKey key: String) {
        try? queue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO kv_setting (key, value) VALUES (?, ?)
                    ON CONFLICT(key) DO UPDATE SET value = excluded.value
                    """,
                arguments: [key, value]
            )
        }
    }
}
