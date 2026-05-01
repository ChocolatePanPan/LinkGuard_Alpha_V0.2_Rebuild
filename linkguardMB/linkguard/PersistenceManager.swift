import Foundation
import SQLite3

/// SQLite 鍵值持久化管理器
/// 使用 JSON 序列化將 Codable 集合存入 SQLite，App 重啟後自動還原資料
final class PersistenceManager {
    static let shared = PersistenceManager()
    private var db: OpaquePointer?

    private init() {
        openDatabase()
        createTable()
    }

    deinit {
        sqlite3_close(db)
    }

    // MARK: - 資料庫生命週期

    private func openDatabase() {
        guard let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("[DB] Documents directory not found")
            return
        }
        let dbPath = docsDir.appendingPathComponent("linkguard_field.sqlite").path
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            print("[DB] Failed to open database at \(dbPath)")
        } else {
            // WAL 模式：更好的並行讀寫
            sqlite3_exec(db, "PRAGMA journal_mode=WAL", nil, nil, nil)
            print("[DB] Database opened: \(dbPath)")
        }
    }

    private func createTable() {
        let sql = """
        CREATE TABLE IF NOT EXISTS kv_store (
            key TEXT PRIMARY KEY,
            json TEXT NOT NULL,
            updated_at REAL NOT NULL DEFAULT 0
        )
        """
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            print("[DB] Failed to create table")
        }
    }

    // MARK: - 泛型 CRUD

    /// 將 Codable 物件以 JSON 存入 SQLite
    func save<T: Encodable>(key: String, value: T) {
        guard let data = try? JSONEncoder().encode(value),
              let json = String(data: data, encoding: .utf8) else { return }
        let sql = "INSERT OR REPLACE INTO kv_store (key, json, updated_at) VALUES (?, ?, ?)"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, (key as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (json as NSString).utf8String, -1, nil)
        sqlite3_bind_double(stmt, 3, Date().timeIntervalSince1970)
        sqlite3_step(stmt)
    }

    /// 從 SQLite 讀取 JSON 並解碼為 Codable 物件
    func load<T: Decodable>(key: String) -> T? {
        let sql = "SELECT json FROM kv_store WHERE key = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, (key as NSString).utf8String, -1, nil)
        guard sqlite3_step(stmt) == SQLITE_ROW,
              let cStr = sqlite3_column_text(stmt, 0) else { return nil }
        let json = String(cString: cStr)
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    /// 刪除指定鍵
    func delete(key: String) {
        let sql = "DELETE FROM kv_store WHERE key = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, (key as NSString).utf8String, -1, nil)
        sqlite3_step(stmt)
    }

    /// 清除所有持久化資料
    func clearAll() {
        sqlite3_exec(db, "DELETE FROM kv_store", nil, nil, nil)
        print("[DB] All data cleared")
    }
}
