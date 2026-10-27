//  Migrations.swift
//  boringNotch

import Foundation
import GRDB

enum DatabaseMigrations {
    static func register(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v1_initial") { db in
            try db.execute(sql: """
                CREATE TABLE clipboard_item (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    content_type TEXT CHECK (content_type IN ('text', 'rtf', 'image', 'file_path', 'url')),
                    content_text TEXT,
                    content_blob BLOB,
                    content_hash TEXT,
                    source_app TEXT,
                    is_pinned INTEGER NOT NULL DEFAULT 0,
                    is_sensitive INTEGER NOT NULL DEFAULT 0,
                    created_at REAL NOT NULL
                )
                """)
            try db.execute(sql: "CREATE INDEX idx_clipboard_hash ON clipboard_item(content_hash)")
            try db.execute(sql: "CREATE INDEX idx_clipboard_pin_time ON clipboard_item(is_pinned, created_at DESC)")
            try db.execute(sql: """
                CREATE VIRTUAL TABLE clipboard_fts USING fts5(
                    content_text,
                    content='clipboard_item',
                    content_rowid='id'
                )
                """)
            try db.execute(sql: """
                CREATE TRIGGER clipboard_fts_insert AFTER INSERT ON clipboard_item BEGIN
                    INSERT INTO clipboard_fts(rowid, content_text) VALUES (new.id, new.content_text);
                END
                """)
            try db.execute(sql: """
                CREATE TRIGGER clipboard_fts_delete AFTER DELETE ON clipboard_item BEGIN
                    INSERT INTO clipboard_fts(clipboard_fts, rowid, content_text) VALUES ('delete', old.id, old.content_text);
                END
                """)
            try db.execute(sql: """
                CREATE TRIGGER clipboard_fts_update AFTER UPDATE ON clipboard_item BEGIN
                    INSERT INTO clipboard_fts(clipboard_fts, rowid, content_text) VALUES ('delete', old.id, old.content_text);
                    INSERT INTO clipboard_fts(rowid, content_text) VALUES (new.id, new.content_text);
                END
                """)

            try db.execute(sql: """
                CREATE TABLE ignored_app (
                    bundle_id TEXT PRIMARY KEY,
                    added_at REAL NOT NULL
                )
                """)
            try db.execute(sql: """
                INSERT INTO ignored_app (bundle_id, added_at) VALUES
                    ('com.1password.1password', strftime('%s', 'now')),
                    ('com.bitwarden.desktop', strftime('%s', 'now')),
                    ('com.apple.keychainaccess', strftime('%s', 'now'))
                """)

            try db.execute(sql: """
                CREATE TABLE pin_group (
                    id TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    sort_order INTEGER DEFAULT 0,
                    created_at REAL NOT NULL
                )
                """)
            try db.execute(sql: """
                CREATE TABLE pin_window (
                    id TEXT PRIMARY KEY,
                    image_path TEXT,
                    pos_x REAL,
                    pos_y REAL,
                    scale REAL DEFAULT 1,
                    opacity REAL DEFAULT 1,
                    rotation REAL DEFAULT 0,
                    flip_h INTEGER DEFAULT 0,
                    flip_v INTEGER DEFAULT 0,
                    grayscale INTEGER DEFAULT 0,
                    inverted INTEGER DEFAULT 0,
                    always_on_top INTEGER DEFAULT 1,
                    bg_mode TEXT DEFAULT 'transparent',
                    thumb_state TEXT,
                    group_id TEXT REFERENCES pin_group(id),
                    kind TEXT DEFAULT 'image' CHECK (kind IN ('image', 'text', 'file', 'color')),
                    source_payload TEXT,
                    space_policy TEXT DEFAULT 'all_spaces',
                    solo_hidden INTEGER DEFAULT 0,
                    is_alive INTEGER DEFAULT 1,
                    created_at REAL NOT NULL
                )
                """)
            try db.execute(sql: """
                CREATE TABLE snip_record (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    file_path TEXT,
                    width INTEGER,
                    height INTEGER,
                    has_annotation INTEGER DEFAULT 0,
                    status TEXT DEFAULT 'completed' CHECK (status IN ('completed', 'aborted')),
                    annotations_json TEXT,
                    bg_image_path TEXT,
                    output_path TEXT,
                    last_rect TEXT,
                    created_at REAL NOT NULL
                )
                """)
            try db.execute(sql: """
                CREATE TABLE annotation_palette (
                    id TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    colors_json TEXT,
                    is_builtin INTEGER DEFAULT 0
                )
                """)
            try db.execute(sql: """
                CREATE TABLE hotkey_binding (
                    action_id TEXT PRIMARY KEY,
                    key_combo TEXT,
                    enabled INTEGER DEFAULT 1,
                    ignore_apps_json TEXT
                )
                """)
            try db.execute(sql: """
                CREATE TABLE corner_trigger (
                    corner TEXT PRIMARY KEY,
                    action_id TEXT
                )
                """)
            try db.execute(sql: """
                CREATE TABLE kv_setting (
                    key TEXT PRIMARY KEY,
                    value TEXT
                )
                """)
            try db.execute(sql: """
                CREATE TABLE meta (
                    key TEXT PRIMARY KEY,
                    value TEXT
                )
                """)
            try db.execute(sql: "INSERT INTO meta (key, value) VALUES ('schema_version', '1')")
        }
    }
}
