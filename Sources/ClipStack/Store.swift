import CryptoKit
import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// SQLite-backed clipboard history. All calls hop onto a serial queue, so the
/// connection is only ever touched from one thread.
final class Store {
    static let shared = Store()

    private var db: OpaquePointer?
    private let q = DispatchQueue(label: "net.local.clipstack.store")

    static var databaseURL: URL {
        // Overridable so screenshots and experiments never touch real history.
        if let override = ProcessInfo.processInfo.environment["CLIPSTACK_DB"] {
            let url = URL(fileURLWithPath: override)
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            return url
        }
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClipStack", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("history.sqlite")
    }

    /// The history holds everything you have ever copied, so it is readable
    /// only by its owner. SQLite would otherwise create it 0644, which lets any
    /// other account on the machine read it.
    private static func restrictPermissions(_ url: URL) {
        let fm = FileManager.default
        try? fm.setAttributes([.posixPermissions: 0o700],
                              ofItemAtPath: url.deletingLastPathComponent().path)
        for suffix in ["", "-wal", "-shm"] {
            let path = url.path + suffix
            guard fm.fileExists(atPath: path) else { continue }
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
        }
    }

    private init() {
        let path = Store.databaseURL.path
        if sqlite3_open(path, &db) != SQLITE_OK {
            NSLog("ClipStack: cannot open \(path): \(lastError)")
        }
        exec("PRAGMA journal_mode = WAL;")
        exec("PRAGMA synchronous = NORMAL;")
        exec("""
        CREATE TABLE IF NOT EXISTS clips (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            kind        TEXT    NOT NULL,
            text        TEXT    NOT NULL DEFAULT '',
            title       TEXT,
            app_name    TEXT,
            app_bundle  TEXT,
            blob        BLOB,
            created_at  REAL    NOT NULL,
            favorite    INTEGER NOT NULL DEFAULT 0,
            fav_order   INTEGER NOT NULL DEFAULT 0,
            digest      TEXT    NOT NULL
        );
        """)
        migrateAddingCustomIcon()
        migrateAddingSearchIndex()
        exec("CREATE INDEX IF NOT EXISTS idx_created ON clips(created_at DESC);")
        exec("CREATE INDEX IF NOT EXISTS idx_digest  ON clips(digest);")
        exec("CREATE INDEX IF NOT EXISTS idx_fav     ON clips(favorite, fav_order);")
        Store.restrictPermissions(Store.databaseURL)
    }

    /// ALTER TABLE errors if the column is already there, so check first
    /// rather than relying on a failed statement.
    private func migrateAddingCustomIcon() {
        var present = false
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "PRAGMA table_info(clips);", -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let name = sqlite3_column_text(stmt, 1),
                   String(cString: name) == "custom_icon" {
                    present = true
                    break
                }
            }
        }
        sqlite3_finalize(stmt)
        if !present {
            exec("ALTER TABLE clips ADD COLUMN custom_icon BLOB;")
        }
    }

    /// A trigram FTS5 index over the searchable columns. Trigram is the one
    /// tokenizer that supports substring matching, so "ompose" still finds
    /// "docker compose" the way the old LIKE scan did — but in constant time
    /// instead of reading every row.
    private func migrateAddingSearchIndex() {
        exec("""
        CREATE VIRTUAL TABLE IF NOT EXISTS clips_fts USING fts5(
            text, title, app_name,
            content='clips', content_rowid='id', tokenize='trigram'
        );
        """)
        exec("""
        CREATE TRIGGER IF NOT EXISTS clips_fts_insert AFTER INSERT ON clips BEGIN
            INSERT INTO clips_fts(rowid, text, title, app_name)
            VALUES (new.id, new.text, new.title, new.app_name);
        END;
        """)
        exec("""
        CREATE TRIGGER IF NOT EXISTS clips_fts_delete AFTER DELETE ON clips BEGIN
            INSERT INTO clips_fts(clips_fts, rowid, text, title, app_name)
            VALUES ('delete', old.id, old.text, old.title, old.app_name);
        END;
        """)
        exec("""
        CREATE TRIGGER IF NOT EXISTS clips_fts_update AFTER UPDATE ON clips BEGIN
            INSERT INTO clips_fts(clips_fts, rowid, text, title, app_name)
            VALUES ('delete', old.id, old.text, old.title, old.app_name);
            INSERT INTO clips_fts(rowid, text, title, app_name)
            VALUES (new.id, new.text, new.title, new.app_name);
        END;
        """)

        // Backfill once. Rebuilding on every launch would cost more than the
        // scan it replaces, so it's gated on the schema version.
        var version: Int32 = 0
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "PRAGMA user_version;", -1, &stmt, nil) == SQLITE_OK,
           sqlite3_step(stmt) == SQLITE_ROW {
            version = sqlite3_column_int(stmt, 0)
        }
        sqlite3_finalize(stmt)
        if version < 1 {
            exec("INSERT INTO clips_fts(clips_fts) VALUES('rebuild');")
            exec("PRAGMA user_version = 1;")
        }
    }

    private var lastError: String { String(cString: sqlite3_errmsg(db)) }

    private func exec(_ sql: String) {
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            NSLog("ClipStack SQL error: \(lastError) — \(sql.prefix(60))")
        }
    }

    // MARK: - Writes

    /// Inserts a clip. If an identical one already exists it is moved back to
    /// the top instead of creating a duplicate. Returns the row id.
    @discardableResult
    func insert(kind: ClipKind, text: String, appName: String?, appBundleID: String?,
                blob: Data?, digest: String) -> Int64 {
        q.sync {
            var existing: Int64 = -1
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, "SELECT id FROM clips WHERE digest = ? LIMIT 1;", -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, digest, -1, SQLITE_TRANSIENT)
                if sqlite3_step(stmt) == SQLITE_ROW { existing = sqlite3_column_int64(stmt, 0) }
            }
            sqlite3_finalize(stmt)

            if existing >= 0 {
                var up: OpaquePointer?
                if sqlite3_prepare_v2(db, "UPDATE clips SET created_at = ? WHERE id = ?;", -1, &up, nil) == SQLITE_OK {
                    sqlite3_bind_double(up, 1, Date().timeIntervalSince1970)
                    sqlite3_bind_int64(up, 2, existing)
                    sqlite3_step(up)
                }
                sqlite3_finalize(up)
                return existing
            }

            var ins: OpaquePointer?
            let sql = """
            INSERT INTO clips (kind, text, app_name, app_bundle, blob, created_at, digest)
            VALUES (?, ?, ?, ?, ?, ?, ?);
            """
            guard sqlite3_prepare_v2(db, sql, -1, &ins, nil) == SQLITE_OK else {
                NSLog("ClipStack: insert prepare failed: \(lastError)")
                return -1
            }
            sqlite3_bind_text(ins, 1, kind.rawValue, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(ins, 2, text, -1, SQLITE_TRANSIENT)
            if let appName { sqlite3_bind_text(ins, 3, appName, -1, SQLITE_TRANSIENT) } else { sqlite3_bind_null(ins, 3) }
            if let appBundleID { sqlite3_bind_text(ins, 4, appBundleID, -1, SQLITE_TRANSIENT) } else { sqlite3_bind_null(ins, 4) }
            if let blob, !blob.isEmpty {
                _ = blob.withUnsafeBytes { raw in
                    sqlite3_bind_blob(ins, 5, raw.baseAddress, Int32(blob.count), SQLITE_TRANSIENT)
                }
            } else {
                sqlite3_bind_null(ins, 5)
            }
            sqlite3_bind_double(ins, 6, Date().timeIntervalSince1970)
            sqlite3_bind_text(ins, 7, digest, -1, SQLITE_TRANSIENT)
            sqlite3_step(ins)
            sqlite3_finalize(ins)
            return sqlite3_last_insert_rowid(db)
        }
    }

    /// Moves a clip to the top of the history without re-recording it.
    func touch(id: Int64) {
        run("UPDATE clips SET created_at = ? WHERE id = ?;") { stmt in
            sqlite3_bind_double(stmt, 1, Date().timeIntervalSince1970)
            sqlite3_bind_int64(stmt, 2, id)
        }
    }

    /// Shifts a clip's timestamp into the past. Only used to seed screenshots.
    func backdate(id: Int64, bySeconds seconds: TimeInterval) {
        run("UPDATE clips SET created_at = ? WHERE id = ?;") { stmt in
            sqlite3_bind_double(stmt, 1, Date().timeIntervalSince1970 - seconds)
            sqlite3_bind_int64(stmt, 2, id)
        }
    }

    func setFavorite(id: Int64, _ favorite: Bool) {
        if favorite {
            var next = 0
            q.sync {
                var stmt: OpaquePointer?
                if sqlite3_prepare_v2(db, "SELECT COALESCE(MAX(fav_order), 0) + 1 FROM clips WHERE favorite = 1;", -1, &stmt, nil) == SQLITE_OK,
                   sqlite3_step(stmt) == SQLITE_ROW {
                    next = Int(sqlite3_column_int(stmt, 0))
                }
                sqlite3_finalize(stmt)
            }
            run("UPDATE clips SET favorite = 1, fav_order = ? WHERE id = ?;") { stmt in
                sqlite3_bind_int(stmt, 1, Int32(next))
                sqlite3_bind_int64(stmt, 2, id)
            }
        } else {
            run("UPDATE clips SET favorite = 0, fav_order = 0 WHERE id = ?;") { stmt in
                sqlite3_bind_int64(stmt, 1, id)
            }
        }
    }

    /// Replaces a clip's text after an edit. The digest is recomputed so a
    /// later copy of the original text doesn't dedupe into the edited row, and
    /// the FTS triggers reindex it automatically.
    func updateText(id: Int64, _ newText: String) {
        let digest = SHA256.hash(data: Data(newText.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        run("UPDATE clips SET text = ?, digest = ? WHERE id = ?;") { stmt in
            sqlite3_bind_text(stmt, 1, newText, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, digest, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 3, id)
        }
    }

    func setCustomIcon(id: Int64, _ png: Data?) {
        run("UPDATE clips SET custom_icon = ? WHERE id = ?;") { stmt in
            if let png, !png.isEmpty {
                _ = png.withUnsafeBytes { raw in
                    sqlite3_bind_blob(stmt, 1, raw.baseAddress, Int32(png.count), SQLITE_TRANSIENT)
                }
            } else {
                sqlite3_bind_null(stmt, 1)
            }
            sqlite3_bind_int64(stmt, 2, id)
        }
    }

    func customIcon(for id: Int64) -> Data? {
        q.sync {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT custom_icon FROM clips WHERE id = ?;", -1, &stmt, nil) == SQLITE_OK
            else { return nil }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int64(stmt, 1, id)
            guard sqlite3_step(stmt) == SQLITE_ROW,
                  let bytes = sqlite3_column_blob(stmt, 0) else { return nil }
            return Data(bytes: bytes, count: Int(sqlite3_column_bytes(stmt, 0)))
        }
    }

    func setTitle(id: Int64, _ title: String?) {
        run("UPDATE clips SET title = ? WHERE id = ?;") { stmt in
            if let title, !title.isEmpty {
                sqlite3_bind_text(stmt, 1, title, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 1)
            }
            sqlite3_bind_int64(stmt, 2, id)
        }
    }

    func delete(id: Int64) {
        run("DELETE FROM clips WHERE id = ?;") { stmt in sqlite3_bind_int64(stmt, 1, id) }
    }

    /// Clears history but never touches favorites.
    func clearHistory() {
        q.sync { exec("DELETE FROM clips WHERE favorite = 0;") }
        vacuum()
    }

    func clearEverything() {
        q.sync { exec("DELETE FROM clips;") }
        vacuum()
    }

    private func vacuum() { q.sync { exec("VACUUM;") } }

    /// Trims non-favorite rows beyond `limit`. `limit <= 0` means unlimited.
    func prune(to limit: Int) {
        guard limit > 0 else { return }
        run("""
        DELETE FROM clips WHERE favorite = 0 AND id NOT IN (
            SELECT id FROM clips WHERE favorite = 0 ORDER BY created_at DESC LIMIT ?
        );
        """) { stmt in sqlite3_bind_int(stmt, 1, Int32(limit)) }
    }

    private func run(_ sql: String, bind: (OpaquePointer?) -> Void) {
        q.sync {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                NSLog("ClipStack: prepare failed: \(lastError)")
                return
            }
            bind(stmt)
            if sqlite3_step(stmt) != SQLITE_DONE {
                NSLog("ClipStack: step failed: \(lastError)")
            }
            sqlite3_finalize(stmt)
        }
    }

    // MARK: - Reads

    private static let columns = """
    c.id, c.kind, c.text, c.title, c.app_name, c.app_bundle, \
    COALESCE(LENGTH(c.blob),0), c.created_at, c.favorite, c.fav_order, c.digest, \
    COALESCE(LENGTH(c.custom_icon),0)
    """

    /// `query` empty returns everything, newest first. Favorites-only flips to
    /// the user's favorite ordering.
    ///
    /// Anything three characters or longer goes through the trigram index, so
    /// search cost is independent of how much history is stored. Shorter
    /// fragments fall back to a scan: the index can't help below a trigram, but
    /// one- and two-character needles match almost everything, so the LIMIT is
    /// reached within the first handful of rows.
    func fetch(query: String, favoritesOnly: Bool, limit: Int = 500) -> [Clip] {
        q.sync {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            let useIndex = trimmed.count >= 3

            var sql = "SELECT \(Store.columns) FROM clips c"
            if useIndex {
                sql += " JOIN clips_fts ON clips_fts.rowid = c.id"
            }

            var clauses: [String] = []
            if favoritesOnly { clauses.append("c.favorite = 1") }
            if useIndex {
                clauses.append("clips_fts MATCH ?")
            } else if !trimmed.isEmpty {
                clauses.append("(lower(c.text) LIKE ? OR lower(COALESCE(c.title,'')) LIKE ? OR lower(COALESCE(c.app_name,'')) LIKE ?)")
            }
            if !clauses.isEmpty { sql += " WHERE " + clauses.joined(separator: " AND ") }
            sql += favoritesOnly ? " ORDER BY c.fav_order ASC, c.created_at DESC"
                                 : " ORDER BY c.created_at DESC"
            sql += " LIMIT \(limit);"

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                NSLog("ClipStack: fetch prepare failed: \(lastError)")
                return []
            }
            defer { sqlite3_finalize(stmt) }

            if useIndex {
                // Trigram FTS treats a quoted phrase as a substring match;
                // doubling quotes keeps a typed " from ending the phrase.
                let phrase = "\"" + trimmed.replacingOccurrences(of: "\"", with: "\"\"") + "\""
                sqlite3_bind_text(stmt, 1, phrase, -1, SQLITE_TRANSIENT)
            } else if !trimmed.isEmpty {
                let needle = "%\(trimmed.lowercased())%"
                for i in Int32(1)...Int32(3) {
                    sqlite3_bind_text(stmt, i, needle, -1, SQLITE_TRANSIENT)
                }
            }

            var out: [Clip] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                out.append(row(stmt))
            }
            return out
        }
    }

    /// Loads one clip's payload. Called only for thumbnails, Quick Look and
    /// pasting — never while drawing the list.
    func blob(for id: Int64) -> Data? {
        q.sync {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT blob FROM clips WHERE id = ?;", -1, &stmt, nil) == SQLITE_OK
            else { return nil }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int64(stmt, 1, id)
            guard sqlite3_step(stmt) == SQLITE_ROW,
                  let bytes = sqlite3_column_blob(stmt, 0) else { return nil }
            return Data(bytes: bytes, count: Int(sqlite3_column_bytes(stmt, 0)))
        }
    }

    func count() -> (total: Int, favorites: Int, bytes: Int64) {
        q.sync {
            var total = 0, favs = 0
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, "SELECT COUNT(*), COALESCE(SUM(favorite), 0) FROM clips;", -1, &stmt, nil) == SQLITE_OK,
               sqlite3_step(stmt) == SQLITE_ROW {
                total = Int(sqlite3_column_int(stmt, 0))
                favs = Int(sqlite3_column_int(stmt, 1))
            }
            sqlite3_finalize(stmt)
            let attrs = try? FileManager.default.attributesOfItem(atPath: Store.databaseURL.path)
            let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
            return (total, favs, size)
        }
    }

    private func row(_ stmt: OpaquePointer?) -> Clip {
        func str(_ i: Int32) -> String? {
            guard let c = sqlite3_column_text(stmt, i) else { return nil }
            return String(cString: c)
        }
        return Clip(
            id: sqlite3_column_int64(stmt, 0),
            kind: ClipKind(rawValue: str(1) ?? "text") ?? .text,
            text: str(2) ?? "",
            title: str(3),
            appName: str(4),
            appBundleID: str(5),
            blobSize: Int(sqlite3_column_int(stmt, 6)),
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 7)),
            favorite: sqlite3_column_int(stmt, 8) == 1,
            favoriteOrder: Int(sqlite3_column_int(stmt, 9)),
            digest: str(10) ?? "",
            customIconSize: Int(sqlite3_column_int(stmt, 11))
        )
    }
}
