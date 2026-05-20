import Foundation
import SwiftUI
import Combine
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

// MARK: - 回放資料模型

struct ReplayPatient: Identifiable {
    let id: String          // patient_id
    let priority: String    // 紅色/黃色/綠色/黑色
    let locationDesc: String
    let reason: String
    let timestamp: String
}

struct ReplayDecision: Identifiable {
    let id: Int
    let timestamp: String
    let decisionText: String
    let triggerType: String
}

struct ReplayWeather {
    let temperature: Double
    let humidity: Double
    let windSpeed: Double
    let rainfall: Double
    let timestamp: String
}

struct ReplayNode: Identifiable {
    let id: String      // node_id
    let battery: Int
    let rssi: Double
    let snr: Double
    let online: Bool
    let timestamp: String
}

struct ReplayTimelineEvent: Identifiable {
    let id: Int
    let timestamp: Date
    let type: String    // decision / patient / report / node / weather
    let summary: String
}

struct ReplaySnapshot {
    var patients: [ReplayPatient] = []
    var latestDecision: ReplayDecision? = nil
    var weather: ReplayWeather? = nil
    var nodes: [ReplayNode] = []
    var recentEvents: [ReplayTimelineEvent] = []
}

// MARK: - ViewModel

@MainActor
final class HQReplayViewModel: ObservableObject {

    // MARK: 狀態

    @Published var dbPath: String? = nil
    @Published var isLoaded = false
    @Published var loadError: String? = nil

    @Published var allEvents: [ReplayTimelineEvent] = []
    @Published var timelineStart: Date? = nil
    @Published var timelineEnd: Date? = nil

    @Published var currentTime: Date = Date()
    @Published var sliderValue: Double = 0          // 0 ... 1

    @Published var isPlaying = false
    @Published var playbackSpeed: Double = 1.0      // 1 / 2 / 4 / 8

    @Published var snapshot: ReplaySnapshot = ReplaySnapshot()

    // MARK: 私有

    private var playbackTimer: AnyCancellable?
    private static let isoFmt: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoFmtBasic: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    // MARK: - 公開 API

    func openFilePicker() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.title = "選擇 linkguard.db"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = []
        panel.allowsOtherFileTypes = true
        panel.nameFieldLabel = "資料庫檔案:"
        if panel.runModal() == .OK, let url = panel.url {
            loadDatabase(at: url.path)
        }
        #endif
    }

    func loadDatabase(at path: String) {
        loadError = nil
        isLoaded = false
        allEvents = []
        dbPath = path

        do {
            let events = try readAllEvents(from: path)
            allEvents = events.sorted { $0.timestamp < $1.timestamp }
            timelineStart = allEvents.first?.timestamp
            timelineEnd = allEvents.last?.timestamp
            if let start = timelineStart {
                currentTime = start
                sliderValue = 0
            }
            isLoaded = true
            fetchSnapshot()
        } catch {
            loadError = "讀取失敗: \(error.localizedDescription)"
        }
    }

    func play() {
        guard isLoaded, let end = timelineEnd else { return }
        if currentTime >= end {
            currentTime = timelineStart ?? currentTime
            sliderValue = 0
        }
        isPlaying = true
        playbackTimer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                let step = self.playbackSpeed
                let next = self.currentTime.addingTimeInterval(step * 60)    // 每秒 = 1*speed 分鐘
                if next >= end {
                    self.currentTime = end
                    self.syncSlider()
                    self.fetchSnapshot()
                    self.pause()
                } else {
                    self.currentTime = next
                    self.syncSlider()
                    self.fetchSnapshot()
                }
            }
    }

    func pause() {
        isPlaying = false
        playbackTimer?.cancel()
        playbackTimer = nil
    }

    func seekToStart() {
        pause()
        if let start = timelineStart { currentTime = start }
        sliderValue = 0
        fetchSnapshot()
    }

    func seekToEnd() {
        pause()
        if let end = timelineEnd { currentTime = end }
        sliderValue = 1
        fetchSnapshot()
    }

    func onSliderChanged(_ value: Double) {
        guard let start = timelineStart, let end = timelineEnd else { return }
        let range = end.timeIntervalSince(start)
        currentTime = start.addingTimeInterval(range * value)
        fetchSnapshot()
    }

    // MARK: - 快照讀取

    func fetchSnapshot() {
        guard let path = dbPath else { return }
        guard let start = timelineStart, let end = timelineEnd, end > start else { return }

        syncSlider()

        let ts = isoString(currentTime)
        var result = ReplaySnapshot()

        withDB(path) { db in
            result.patients = queryPatients(db: db, until: ts)
            result.latestDecision = queryLatestDecision(db: db, until: ts)
            result.weather = queryLatestWeather(db: db, until: ts)
            result.nodes = queryLatestNodes(db: db, until: ts)
            result.recentEvents = allEvents.filter { $0.timestamp <= currentTime }.suffix(30).reversed()
        }

        snapshot = result
    }

    // MARK: - 私有：同步 slider

    private func syncSlider() {
        guard let start = timelineStart, let end = timelineEnd, end > start else { return }
        let range = end.timeIntervalSince(start)
        sliderValue = max(0, min(1, currentTime.timeIntervalSince(start) / range))
    }

    // MARK: - 私有：SQLite 讀取

    private func withDB(_ path: String, _ block: (OpaquePointer) -> Void) {
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let db else { return }
        defer { sqlite3_close(db) }
        block(db)
    }

    private func readAllEvents(from path: String) throws -> [ReplayTimelineEvent] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let db else {
            throw NSError(domain: "HQReplay", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "無法開啟資料庫"])
        }
        defer { sqlite3_close(db) }

        var events: [ReplayTimelineEvent] = []

        let tables: [(sql: String, type: String)] = [
            ("SELECT id, timestamp, substr(decision_text,1,60) FROM decisions ORDER BY timestamp", "decision"),
            ("SELECT id, timestamp, patient_id || ' (' || priority || ')' FROM patients ORDER BY timestamp", "patient"),
            ("SELECT id, timestamp, report_id || ' - ' || COALESCE(sender_name,'') FROM reports ORDER BY timestamp", "report"),
            ("SELECT id, timestamp, 'Node ' || node_id || ' 🔋' || battery || '%' FROM node_status_log ORDER BY timestamp", "node"),
            ("SELECT id, timestamp, COALESCE(temperature,'?') || '°C ' || COALESCE(humidity,'?') || '%' FROM weather_log ORDER BY timestamp", "weather"),
        ]

        var seq = 0
        for (sql, type) in tables {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
                  let stmt else { continue }
            defer { sqlite3_finalize(stmt) }
            while sqlite3_step(stmt) == SQLITE_ROW {
                let tsRaw = columnText(stmt, 1)
                let summary = columnText(stmt, 2)
                guard let date = parseDate(tsRaw) else { continue }
                seq += 1
                events.append(ReplayTimelineEvent(
                    id: seq,
                    timestamp: date,
                    type: type,
                    summary: summary
                ))
            }
        }
        return events
    }

    private func queryPatients(db: OpaquePointer, until ts: String) -> [ReplayPatient] {
        let sql = """
            SELECT patient_id, priority, COALESCE(location_desc,''), COALESCE(reason,''), timestamp
            FROM patients WHERE timestamp <= ? ORDER BY patient_id
            """
        return queryRows(db: db, sql: sql, params: [ts]) { stmt in
            ReplayPatient(
                id: columnText(stmt, 0),
                priority: columnText(stmt, 1),
                locationDesc: columnText(stmt, 2),
                reason: columnText(stmt, 3),
                timestamp: columnText(stmt, 4)
            )
        }
    }

    private func queryLatestDecision(db: OpaquePointer, until ts: String) -> ReplayDecision? {
        let sql = """
            SELECT id, timestamp, decision_text, COALESCE(trigger_type,'')
            FROM decisions WHERE timestamp <= ? ORDER BY timestamp DESC LIMIT 1
            """
        return queryRows(db: db, sql: sql, params: [ts]) { stmt in
            ReplayDecision(
                id: Int(sqlite3_column_int(stmt, 0)),
                timestamp: columnText(stmt, 1),
                decisionText: columnText(stmt, 2),
                triggerType: columnText(stmt, 3)
            )
        }.first
    }

    private func queryLatestWeather(db: OpaquePointer, until ts: String) -> ReplayWeather? {
        let sql = """
            SELECT COALESCE(temperature,0), COALESCE(humidity,0),
                   COALESCE(wind_speed,0), COALESCE(rainfall,0), timestamp
            FROM weather_log WHERE timestamp <= ? ORDER BY timestamp DESC LIMIT 1
            """
        return queryRows(db: db, sql: sql, params: [ts]) { stmt in
            ReplayWeather(
                temperature: sqlite3_column_double(stmt, 0),
                humidity: sqlite3_column_double(stmt, 1),
                windSpeed: sqlite3_column_double(stmt, 2),
                rainfall: sqlite3_column_double(stmt, 3),
                timestamp: columnText(stmt, 4)
            )
        }.first
    }

    private func queryLatestNodes(db: OpaquePointer, until ts: String) -> [ReplayNode] {
        let sql = """
            SELECT n.node_id, COALESCE(n.battery,0), COALESCE(n.rssi,0),
                   COALESCE(n.snr,0), COALESCE(n.online,0), n.timestamp
            FROM node_status_log n
            INNER JOIN (
                SELECT node_id, MAX(id) as max_id
                FROM node_status_log WHERE timestamp <= ?
                GROUP BY node_id
            ) latest ON n.id = latest.max_id
            """
        return queryRows(db: db, sql: sql, params: [ts]) { stmt in
            ReplayNode(
                id: columnText(stmt, 0),
                battery: Int(sqlite3_column_int(stmt, 1)),
                rssi: sqlite3_column_double(stmt, 2),
                snr: sqlite3_column_double(stmt, 3),
                online: sqlite3_column_int(stmt, 4) != 0,
                timestamp: columnText(stmt, 5)
            )
        }
    }

    private func queryRows<T>(db: OpaquePointer, sql: String, params: [String],
                               map: (OpaquePointer) -> T) -> [T] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
              let stmt else { return [] }
        defer { sqlite3_finalize(stmt) }
        for (i, p) in params.enumerated() {
            sqlite3_bind_text(stmt, Int32(i + 1), p, -1, sqliteTransient)
        }
        var results: [T] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            results.append(map(stmt))
        }
        return results
    }

    // MARK: - 工具

    private func columnText(_ stmt: OpaquePointer, _ col: Int32) -> String {
        guard let ptr = sqlite3_column_text(stmt, col) else { return "" }
        return String(cString: ptr)
    }

    private func parseDate(_ raw: String) -> Date? {
        if let d = Self.isoFmt.date(from: raw) { return d }
        if let d = Self.isoFmtBasic.date(from: raw) { return d }
        // 嘗試 "YYYY-MM-DD HH:mm:ss" 格式
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Taipei")
        return f.date(from: raw)
    }

    private func isoString(_ date: Date) -> String {
        Self.isoFmt.string(from: date)
    }
}
