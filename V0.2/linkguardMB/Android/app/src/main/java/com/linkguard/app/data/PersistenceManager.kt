package com.linkguard.app.data

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject

/**
 * 輕量 SQLite KV 持久化管理器 — 對應 iOS PersistenceManager
 *
 * 使用 key-value 模式存 JSON，WAL 模式提升並發效能。
 * 用於傷患回報、SOS 紀錄、命令歷史等離線資料存儲。
 */
class PersistenceManager private constructor(context: Context) :
    SQLiteOpenHelper(context.applicationContext, DB_NAME, null, DB_VERSION) {

    companion object {
        private const val DB_NAME = "linkguard_kv.db"
        private const val DB_VERSION = 1
        private const val TABLE = "kv_store"
        private const val TAG = "PersistenceManager"

        @Volatile
        private var instance: PersistenceManager? = null

        fun getInstance(context: Context): PersistenceManager =
            instance ?: synchronized(this) {
                instance ?: PersistenceManager(context).also { instance = it }
            }
    }

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL("""
            CREATE TABLE IF NOT EXISTS $TABLE (
                key TEXT PRIMARY KEY,
                json TEXT NOT NULL,
                updated_at REAL NOT NULL DEFAULT 0
            )
        """.trimIndent())
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        // 未來升級用
    }

    override fun onOpen(db: SQLiteDatabase) {
        super.onOpen(db)
        db.enableWriteAheadLogging()
    }

    // === CRUD ===

    /** 儲存 JSON 字串 */
    fun save(key: String, json: String) {
        try {
            writableDatabase.execSQL(
                "INSERT OR REPLACE INTO $TABLE (key, json, updated_at) VALUES (?, ?, ?)",
                arrayOf(key, json, System.currentTimeMillis() / 1000.0)
            )
        } catch (e: Exception) {
            Log.e(TAG, "save($key) failed: ${e.message}")
        }
    }

    /** 儲存 JSONArray */
    fun saveArray(key: String, array: JSONArray) {
        save(key, array.toString())
    }

    /** 儲存 JSONObject */
    fun saveObject(key: String, obj: JSONObject) {
        save(key, obj.toString())
    }

    /** 讀取原始 JSON 字串 */
    fun load(key: String): String? {
        return try {
            readableDatabase.rawQuery(
                "SELECT json FROM $TABLE WHERE key = ?", arrayOf(key)
            ).use { cursor ->
                if (cursor.moveToFirst()) cursor.getString(0) else null
            }
        } catch (e: Exception) {
            Log.e(TAG, "load($key) failed: ${e.message}")
            null
        }
    }

    /** 讀取為 JSONArray */
    fun loadArray(key: String): JSONArray? {
        val raw = load(key) ?: return null
        return try {
            JSONArray(raw)
        } catch (e: Exception) {
            Log.e(TAG, "loadArray($key) parse failed: ${e.message}")
            null
        }
    }

    /** 讀取為 JSONObject */
    fun loadObject(key: String): JSONObject? {
        val raw = load(key) ?: return null
        return try {
            JSONObject(raw)
        } catch (e: Exception) {
            Log.e(TAG, "loadObject($key) parse failed: ${e.message}")
            null
        }
    }

    /** 刪除指定 key */
    fun delete(key: String) {
        try {
            writableDatabase.execSQL("DELETE FROM $TABLE WHERE key = ?", arrayOf(key))
        } catch (e: Exception) {
            Log.e(TAG, "delete($key) failed: ${e.message}")
        }
    }

    /** 清空全部資料 */
    fun clearAll() {
        try {
            writableDatabase.execSQL("DELETE FROM $TABLE")
        } catch (e: Exception) {
            Log.e(TAG, "clearAll failed: ${e.message}")
        }
    }

    /**
     * 從 SharedPreferences 遷移既有資料到 SQLite（一次性）。
     * 遷移後在 SharedPreferences 寫入標記避免重複。
     */
    fun migrateFromSharedPreferences(context: Context) {
        val prefs = context.getSharedPreferences("linkguard_prefs", Context.MODE_PRIVATE)
        if (prefs.getBoolean("sqlite_migrated", false)) return

        // 遷移 local_patients
        prefs.getString("local_patients", null)?.let { json ->
            save("localPatients", json)
        }

        prefs.edit().putBoolean("sqlite_migrated", true).apply()
        Log.i(TAG, "SharedPreferences → SQLite 遷移完成")
    }
}
