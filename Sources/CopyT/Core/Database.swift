import Foundation
import SQLite3

enum DBError: LocalizedError {
    case open(String)
    case exec(String)

    var errorDescription: String? {
        switch self {
        case .open(let m): return "无法打开数据库：\(m)"
        case .exec(let m): return "数据库错误：\(m)"
        }
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum SQLValue {
    case text(String)
    case int(Int64)
    case double(Double)
    case null
}

struct ClipFilter {
    var search: String = ""
    var kind: ClipKind?
    var day: String?
    var pinnedOnly = false
}

/// 基于系统 SQLite 的轻量存储，无第三方依赖
final class Database {
    static let fileName = "copyt.sqlite"

    private var db: OpaquePointer?
    let url: URL

    init(url: URL) throws {
        self.url = url
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(url.path, &db, flags, nil) != SQLITE_OK {
            let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            sqlite3_close(db)
            db = nil
            throw DBError.open(msg)
        }
        try exec("PRAGMA journal_mode=WAL;")
        try exec("""
        CREATE TABLE IF NOT EXISTS items (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            kind        TEXT    NOT NULL,
            text        TEXT,
            data_path   TEXT,
            source_app  TEXT,
            created_at  REAL    NOT NULL,
            day         TEXT    NOT NULL,
            hash        TEXT    NOT NULL,
            byte_size   INTEGER NOT NULL DEFAULT 0,
            pinned      INTEGER NOT NULL DEFAULT 0
        );
        CREATE INDEX IF NOT EXISTS idx_items_day ON items(day);
        CREATE INDEX IF NOT EXISTS idx_items_created ON items(created_at);
        CREATE INDEX IF NOT EXISTS idx_items_hash ON items(hash);
        """)
    }

    deinit { close() }

    func close() {
        if let db { sqlite3_close_v2(db) }
        db = nil
    }

    /// 合并 WAL，便于移动数据库文件
    func checkpoint() {
        try? exec("PRAGMA wal_checkpoint(TRUNCATE);")
    }

    // MARK: - 基础

    private var errorMessage: String {
        db.map { String(cString: sqlite3_errmsg($0)) } ?? "database closed"
    }

    func exec(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? errorMessage
            sqlite3_free(err)
            throw DBError.exec(msg)
        }
    }

    private func prepare(_ sql: String, _ args: [SQLValue]) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw DBError.exec(errorMessage)
        }
        for (i, arg) in args.enumerated() {
            let idx = Int32(i + 1)
            switch arg {
            case .text(let s): sqlite3_bind_text(stmt, idx, s, -1, SQLITE_TRANSIENT)
            case .int(let v): sqlite3_bind_int64(stmt, idx, v)
            case .double(let v): sqlite3_bind_double(stmt, idx, v)
            case .null: sqlite3_bind_null(stmt, idx)
            }
        }
        return stmt
    }

    private func run(_ sql: String, _ args: [SQLValue] = []) throws {
        let stmt = try prepare(sql, args)
        defer { sqlite3_finalize(stmt) }
        let rc = sqlite3_step(stmt)
        guard rc == SQLITE_DONE || rc == SQLITE_ROW else { throw DBError.exec(errorMessage) }
    }

    private func query<T>(_ sql: String, _ args: [SQLValue] = [], map: (OpaquePointer) -> T?) throws -> [T] {
        let stmt = try prepare(sql, args)
        defer { sqlite3_finalize(stmt) }
        var result: [T] = []
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_ROW {
                if let v = map(stmt) { result.append(v) }
            } else if rc == SQLITE_DONE {
                break
            } else {
                throw DBError.exec(errorMessage)
            }
        }
        return result
    }

    private static func text(_ stmt: OpaquePointer, _ i: Int32) -> String? {
        guard let c = sqlite3_column_text(stmt, i) else { return nil }
        return String(cString: c)
    }

    private static let columns = "id, kind, text, data_path, source_app, created_at, day, hash, byte_size, pinned"

    private static func item(_ s: OpaquePointer) -> ClipItem? {
        guard let kind = ClipKind(rawValue: text(s, 1) ?? "") else { return nil }
        return ClipItem(
            id: sqlite3_column_int64(s, 0),
            kind: kind,
            text: text(s, 2),
            dataPath: text(s, 3),
            sourceApp: text(s, 4),
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(s, 5)),
            day: text(s, 6) ?? "",
            hash: text(s, 7) ?? "",
            byteSize: Int(sqlite3_column_int64(s, 8)),
            pinned: sqlite3_column_int64(s, 9) != 0
        )
    }

    private static func opt(_ s: String?) -> SQLValue { s.map { .text($0) } ?? .null }

    // MARK: - 业务

    @discardableResult
    func insert(_ c: Capture, dataPath: String?, date: Date) throws -> Int64 {
        try run(
            "INSERT INTO items (kind, text, data_path, source_app, created_at, day, hash, byte_size) VALUES (?,?,?,?,?,?,?,?)",
            [.text(c.kind.rawValue), Self.opt(c.text), Self.opt(dataPath), Self.opt(c.sourceApp),
             .double(date.timeIntervalSince1970), .text(DayFormatter.string(date)), .text(c.hash), .int(Int64(c.byteSize))]
        )
        return sqlite3_last_insert_rowid(db)
    }

    func item(withHash hash: String) throws -> ClipItem? {
        try query("SELECT \(Self.columns) FROM items WHERE hash = ? ORDER BY created_at DESC LIMIT 1",
                  [.text(hash)], map: Self.item).first
    }

    /// 重复内容再次复制时，移到最新并归入今天
    func touch(id: Int64, date: Date, sourceApp: String?) throws {
        try run("UPDATE items SET created_at = ?, day = ?, source_app = COALESCE(?, source_app) WHERE id = ?",
                [.double(date.timeIntervalSince1970), .text(DayFormatter.string(date)), Self.opt(sourceApp), .int(id)])
    }

    func items(_ f: ClipFilter, limit: Int) throws -> [ClipItem] {
        var conditions: [String] = []
        var args: [SQLValue] = []
        let search = f.search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !search.isEmpty {
            // 支持空格分隔的多关键词（AND）
            for word in search.split(whereSeparator: \.isWhitespace) {
                let escaped = String(word)
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "%", with: "\\%")
                    .replacingOccurrences(of: "_", with: "\\_")
                conditions.append("(text LIKE ? ESCAPE '\\' OR source_app LIKE ? ESCAPE '\\')")
                args.append(.text("%\(escaped)%"))
                args.append(.text("%\(escaped)%"))
            }
        }
        if let kind = f.kind {
            conditions.append("kind = ?")
            args.append(.text(kind.rawValue))
        }
        if let day = f.day {
            conditions.append("day = ?")
            args.append(.text(day))
        }
        if f.pinnedOnly { conditions.append("pinned = 1") }
        let whereSQL = conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")
        args.append(.int(Int64(limit)))
        return try query("SELECT \(Self.columns) FROM items \(whereSQL) ORDER BY created_at DESC LIMIT ?",
                         args, map: Self.item)
    }

    func dayCounts() throws -> [DayCount] {
        try query("SELECT day, COUNT(*) FROM items GROUP BY day ORDER BY day DESC") { s in
            DayCount(day: Self.text(s, 0) ?? "", count: Int(sqlite3_column_int64(s, 1)))
        }
    }

    func totalCount() throws -> Int {
        try query("SELECT COUNT(*) FROM items") { Int(sqlite3_column_int64($0, 0)) }.first ?? 0
    }

    func setPinned(id: Int64, _ pinned: Bool) throws {
        try run("UPDATE items SET pinned = ? WHERE id = ?", [.int(pinned ? 1 : 0), .int(id)])
    }

    func delete(id: Int64) throws {
        try run("DELETE FROM items WHERE id = ?", [.int(id)])
    }

    /// 早于某个时间且未收藏的记录
    func unpinnedItems(before date: Date?) throws -> [ClipItem] {
        if let date {
            return try query("SELECT \(Self.columns) FROM items WHERE pinned = 0 AND created_at < ?",
                             [.double(date.timeIntervalSince1970)], map: Self.item)
        }
        return try query("SELECT \(Self.columns) FROM items WHERE pinned = 0", map: Self.item)
    }

    func deleteUnpinned(before date: Date?) throws {
        if let date {
            try run("DELETE FROM items WHERE pinned = 0 AND created_at < ?", [.double(date.timeIntervalSince1970)])
        } else {
            try run("DELETE FROM items WHERE pinned = 0")
        }
    }
}
