//
//  BackendSupervisor.swift
//  LinkGuardHQ
//
//  Manages the embedded Python backend (macos/*.py) as a tree of child
//  processes. Lets users start, stop, restart, and inspect each service
//  from inside the HQ app instead of running `start_all.sh` in Terminal.
//
//  macOS only. iOS builds compile this as a no-op stub.
//

import Foundation
import Combine

#if os(macOS)
import AppKit

// MARK: - Service definitions

/// One Python backend service that BackendSupervisor knows how to launch.
struct BackendServiceSpec: Identifiable, Hashable {
    static let aiServiceID = "gemma4_server"
    static let pythonWhisperServiceID = "whisper_server"

    let id: String              // canonical key, e.g. "gemma4_server"
    let displayName: String     // shown in UI
    let scriptName: String      // file under backend dir, e.g. "gemma4_server.py"
    let port: Int               // primary port (for health probe / display)
    let isHTTP: Bool            // true → probe via /health; false → TCP connect
    let startDelay: TimeInterval // pre-launch delay, mirrors macos/start_all.sh
    let isHighPower: Bool       // true → start on demand to reduce idle energy

    init(id: String, displayName: String, scriptName: String, port: Int,
         isHTTP: Bool, startDelay: TimeInterval, isHighPower: Bool = false) {
        self.id = id
        self.displayName = displayName
        self.scriptName = scriptName
        self.port = port
        self.isHTTP = isHTTP
        self.startDelay = startDelay
        self.isHighPower = isHighPower
    }

    /// Mac HQ already owns 8003 (speech), 8005 (LGAP audio), and 9001 (UDP audio).
    /// Keep the embedded Python sidecar to services that do not collide with those
    /// native HQ listeners while still covering AI, TCP bridge, resources, photos,
    /// MQTT/LoRa, and optional Python Whisper.
    static let all: [BackendServiceSpec] = [
        .init(id: "mqtt_broker",    displayName: "MQTT Client",        scriptName: "mqtt_broker.py",    port: 1883, isHTTP: false, startDelay: 0),
        .init(id: "tcp_server",     displayName: "TCP Aggregator",     scriptName: "tcp_server.py",     port: 9000, isHTTP: false, startDelay: 0),
        .init(id: Self.aiServiceID,  displayName: "Gemma4 AI",          scriptName: "gemma4_server.py",  port: 8001, isHTTP: true,  startDelay: 2, isHighPower: true),
        .init(id: Self.pythonWhisperServiceID, displayName: "Whisper Voice", scriptName: "whisper_server.py", port: 8002, isHTTP: true, startDelay: 0, isHighPower: true),
        .init(id: "photo_server",   displayName: "Photo Server",       scriptName: "photo_server.py",   port: 8004, isHTTP: true,  startDelay: 2),
        .init(id: "resource_server",displayName: "Resource Server",    scriptName: "resource_server.py",port: 8006, isHTTP: true,  startDelay: 0),
    ]

    static var defaultStartup: [BackendServiceSpec] {
        all.filter { !$0.isHighPower }
    }
}

enum LocalAIModelProfile: String, CaseIterable, Identifiable {
    case singleE4B = "e4b"
    case single26B = "26b"
    case dualE4B = "e4b_dual"
    case fiveE2B = "e2b_five"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .singleE4B: return "E4B"
        case .single26B: return "26B"
        case .dualE4B: return "E4B + E4B（雙執行緒）"
        case .fiveE2B: return "E2B × 5（五並行）"
        }
    }

    var runtimeModel: String {
        switch self {
        case .singleE4B, .dualE4B: return "gemma4:e4b"
        case .single26B: return "gemma4:26b"
        case .fiveE2B: return "gemma4:e2b"
        }
    }

    var parallelWorkers: Int {
        switch self {
        case .singleE4B, .single26B: return 1
        case .dualE4B: return 2
        case .fiveE2B: return 5
        }
    }

    var summary: String {
        switch self {
        case .singleE4B:
            return "單一 E4B，低延遲、適合一般指揮對話。"
        case .single26B:
            return "單一 26B，深度分析優先，耗用資源較高。"
        case .dualE4B:
            return "同時啟動 2 個 E4B 推理 worker，取較完整回覆。"
        case .fiveE2B:
            return "同時啟動 5 個 E2B 推理 worker，適合快速多並行回覆。"
        }
    }

    var environment: [String: String] {
        [
            "LINKGUARD_AI_PROFILE": rawValue,
            "LINKGUARD_OLLAMA_MODEL": runtimeModel,
            "LINKGUARD_AI_PARALLEL_MODEL": runtimeModel,
            "LINKGUARD_AI_PARALLEL_WORKERS": "\(parallelWorkers)",
        ]
    }
}

enum BackendServiceStatus: String {
    case stopped, starting, healthy, unhealthy, crashed
}

struct BackendProcessMetrics: Equatable, Sendable {
    let cpu: String
    let memMB: String

    static let empty = BackendProcessMetrics(cpu: "", memMB: "")
}

/// Mutable per-service runtime state observed by SwiftUI.
@MainActor
final class BackendServiceState: ObservableObject, Identifiable {
    let spec: BackendServiceSpec
    var id: String { spec.id }

    @Published var status: BackendServiceStatus = .stopped
    @Published var pid: Int32? = nil
    @Published var restartCount: Int = 0
    @Published var lastError: String? = nil
    @Published var logTail: [String] = []   // ring buffer, capped to 200 lines
    @Published var startedAt: Date? = nil
    @Published var lastHealthCheck: Date? = nil

    init(spec: BackendServiceSpec) { self.spec = spec }

    fileprivate func appendLogLines(_ lines: [String]) {
        guard !lines.isEmpty else { return }
        logTail.append(contentsOf: lines)
        if logTail.count > 200 { logTail.removeFirst(logTail.count - 200) }
    }
}

// MARK: - Supervisor

@MainActor
final class BackendSupervisor: ObservableObject {
    static let backendDirOverrideKey = "hq.backendDirOverride"

    /// Where to find the Python scripts. On a packaged build this is
    /// `~/Library/Application Support/LinkGuardHQ/backend`. In a dev build
    /// running from Xcode, it falls back to the repository `macos/` folder if
    /// `~/Library/...` doesn't exist yet.
    @Published var backendDir: URL
    @Published var pythonExecutable: URL?
    @Published var services: [BackendServiceState]
    @Published var allHealthy: Bool = false
    @Published var anyCrashed: Bool = false
    @Published var isAIServicePausedForPowerSaving: Bool = false
    @Published var isManualAIPowerSavingModeEnabled: Bool = false
    @Published var aiServicePauseReason: String? = nil
    @Published private var processMetrics: [String: BackendProcessMetrics] = [:]

    private var processes: [String: Process] = [:]
    private var stdoutPipes: [String: Pipe] = [:]
    private var healthTimer: Timer?
    private var metricsTimer: Timer?
    private var aiShouldResumeAfterPause = false

    var isAIServicePaused: Bool {
        isAIServicePausedForPowerSaving || isManualAIPowerSavingModeEnabled
    }

    init() {
        self.services = BackendServiceSpec.all.map { BackendServiceState(spec: $0) }
        self.backendDir = Self.resolveBackendDir()
        self.pythonExecutable = Self.resolvePython(under: backendDir)
        // Cleanly stop child processes when the app is terminating.
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleTerminate),
            name: NSApplication.willTerminateNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handlePowerStateDidChange),
            name: Notification.Name.NSProcessInfoPowerStateDidChange, object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(handleWillSleep),
            name: NSWorkspace.willSleepNotification, object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(handleDidWake),
            name: NSWorkspace.didWakeNotification, object: nil
        )
        updatePowerSavingPauseState()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        // Best effort, can't await on MainActor here.
        for p in processes.values where p.isRunning { p.terminate() }
    }

    // MARK: - Path resolution

    /// Preferred layout: bundled `backend/` resource → copied on first launch
    /// to `~/Library/Application Support/LinkGuardHQ/backend/`.
    static func resolveBackendDir() -> URL {
        if let override = storedBackendDirOverride() {
            return override
        }
        return resolveDefaultBackendDir()
    }

    static func resolveDefaultBackendDir() -> URL {
        let fm = FileManager.default
        // 1) User Application Support copy (preferred at runtime).
        if let appSupport = try? fm.url(for: .applicationSupportDirectory,
                                         in: .userDomainMask,
                                         appropriateFor: nil, create: true) {
            let dest = appSupport.appendingPathComponent("LinkGuardHQ/backend",
                                                          isDirectory: true)
            // Bootstrap from bundle if missing.
            if !fm.fileExists(atPath: dest.path),
               let bundled = Bundle.main.url(forResource: "backend",
                                              withExtension: nil) {
                try? fm.createDirectory(at: dest.deletingLastPathComponent(),
                                         withIntermediateDirectories: true)
                try? fm.copyItem(at: bundled, to: dest)
            }
            if fm.fileExists(atPath: dest.path) { return dest }
        }
        // 2) Bundled resource directly (fallback if AppSupport fails).
        if let bundled = Bundle.main.url(forResource: "backend",
                                          withExtension: nil) {
            return bundled
        }
        // 3) Dev fallback: locate the repository from this Swift source path.
        let sourceFile = URL(fileURLWithPath: #filePath)
        let sourceRoot = sourceFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceMacos = sourceRoot.appendingPathComponent("macos", isDirectory: true)
        if fm.fileExists(atPath: sourceMacos.path) { return sourceMacos }

        // 4) Last fallback: ../../../macos relative to the running binary.
        let bin = Bundle.main.bundleURL.deletingLastPathComponent()
        return bin.appendingPathComponent("../../../macos", isDirectory: true)
                   .standardizedFileURL
    }

    static func storedBackendDirOverride() -> URL? {
        guard let path = UserDefaults.standard.string(forKey: backendDirOverrideKey),
              !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let url = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        return isUsableBackendDir(url) ? url : nil
    }

    static func isUsableBackendDir(_ url: URL) -> Bool {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else { return false }
        return fm.fileExists(atPath: url.appendingPathComponent("requirements.txt").path) &&
            BackendServiceSpec.all.allSatisfy { spec in
                fm.fileExists(atPath: url.appendingPathComponent(spec.scriptName).path)
            }
    }

    var isUsingCustomBackendDir: Bool {
        Self.storedBackendDirOverride()?.path == backendDir.standardizedFileURL.path
    }

    func setBackendDirOverride(_ url: URL) {
        stopAll()
        let standardizedURL = url.standardizedFileURL
        UserDefaults.standard.set(standardizedURL.path, forKey: Self.backendDirOverrideKey)
        backendDir = standardizedURL
        pythonExecutable = Self.resolvePython(under: backendDir)
        resetServiceRuntimeState()
        recomputeAggregate()
    }

    func resetBackendDirOverride() {
        stopAll()
        UserDefaults.standard.removeObject(forKey: Self.backendDirOverrideKey)
        backendDir = Self.resolveDefaultBackendDir()
        pythonExecutable = Self.resolvePython(under: backendDir)
        resetServiceRuntimeState()
        recomputeAggregate()
    }

    private func resetServiceRuntimeState() {
        for state in services {
            state.pid = nil
            state.restartCount = 0
            state.lastError = nil
            state.logTail.removeAll()
            state.startedAt = nil
            state.lastHealthCheck = nil
            state.status = .stopped
        }
        processMetrics.removeAll()
    }

    /// Try the per-app venv first, then Homebrew, then system Python.
    static func resolvePython(under backendDir: URL) -> URL? {
        let fm = FileManager.default
        let candidates: [String] = [
            backendDir.deletingLastPathComponent()
                      .appendingPathComponent(".venv/bin/python3").path,
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3",
        ]
        for c in candidates where fm.isExecutableFile(atPath: c) {
            return URL(fileURLWithPath: c)
        }
        return nil
    }

    // MARK: - Lifecycle

    /// Start every service in the order/delays from `macos/start_all.sh`.
    func startAll() {
        startServices(BackendServiceSpec.all)
    }

    /// Start only the always-on bridge services. AI and Python Whisper are
    /// started on demand because they dominate idle energy use on macOS.
    func startEnergyEfficientServices() {
        startServices(BackendServiceSpec.defaultStartup)
    }

    func startAIServiceIfNeeded() {
        start(BackendServiceSpec.aiServiceID)
    }

    func startPythonWhisperIfNeeded() {
        start(BackendServiceSpec.pythonWhisperServiceID)
    }

    private func startServices(_ specs: [BackendServiceSpec]) {
        Task {
            for spec in specs {
                if spec.startDelay > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(spec.startDelay * 1_000_000_000))
                }
                start(spec.id)
            }
            startHealthLoop()
            startMetricsLoop()
        }
    }

    func stopAll() {
        aiShouldResumeAfterPause = false
        isManualAIPowerSavingModeEnabled = false
        for spec in BackendServiceSpec.all { stop(spec.id) }
        aiServicePauseReason = currentAIServicePauseReason
        stopHealthLoop()
        stopMetricsLoop()
    }

    func start(_ id: String) {
        guard let state = services.first(where: { $0.id == id }) else { return }
        if id == BackendServiceSpec.aiServiceID {
            if ProcessInfo.processInfo.isLowPowerModeEnabled {
                isAIServicePausedForPowerSaving = true
            }
            if isAIServicePaused {
                aiShouldResumeAfterPause = true
                aiServicePauseReason = currentAIServicePauseReason
                state.status = .stopped
                state.lastError = currentAIServicePauseReason
                recomputeAggregate()
                return
            }
        }
        guard state.pid == nil && state.status != .starting && state.status != .healthy else { return }
        guard let python = pythonExecutable else {
            state.lastError = "Python interpreter not found (see Setup Assistant)"
            state.status = .crashed
            return
        }
        let script = backendDir.appendingPathComponent(state.spec.scriptName)
        guard FileManager.default.fileExists(atPath: script.path) else {
            state.lastError = "Missing script: \(script.path)"
            state.status = .crashed
            return
        }

        let p = Process()
        p.executableURL = python
        p.arguments = [script.path]
        p.currentDirectoryURL = backendDir
        if id == BackendServiceSpec.aiServiceID {
            let profile = applyStoredAIModelProfile(restartIfRunning: false)
            var environment = ProcessInfo.processInfo.environment
            profile.environment.forEach { environment[$0.key] = $0.value }
            p.environment = environment
        }

        // Forward stdout & stderr into the per-service ring buffer.
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self, weak state, serviceID = id, weak pipe] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                Task { @MainActor [weak self, weak state, weak pipe] in
                    guard let self else { return }
                    if let pipe, self.stdoutPipes[serviceID] === pipe {
                        self.stdoutPipes.removeValue(forKey: serviceID)
                    }
                    state?.appendLogLines(["[system] log stream closed"])
                }
                return
            }
            guard let chunk = String(data: data, encoding: .utf8) else { return }
            let lines = chunk.split(whereSeparator: \.isNewline).map(String.init)
            Task { @MainActor [weak state] in
                guard let state else { return }
                state.appendLogLines(lines)
            }
        }

        p.terminationHandler = { [weak self, weak state, serviceID = id, weak pipe] proc in
            Task { @MainActor [weak self, weak state, weak pipe] in
                guard let self, let state else { return }
                let code = proc.terminationStatus
                if state.status != .stopped {
                    state.status = .crashed
                    state.lastError = "exited with code \(code)"
                    self.recomputeAggregate()
                }
                if self.processes[serviceID] === proc {
                    self.processes.removeValue(forKey: serviceID)
                }
                if let pipe, self.stdoutPipes[serviceID] === pipe {
                    pipe.fileHandleForReading.readabilityHandler = nil
                    self.stdoutPipes.removeValue(forKey: serviceID)
                }
                state.pid = nil
            }
        }

        do {
            state.status = .starting
            state.lastError = nil
            state.startedAt = Date()
            try p.run()
            state.pid = p.processIdentifier
            processes[id] = p
            stdoutPipes[id] = pipe
            startHealthLoop()
            startMetricsLoop()
        } catch {
            state.status = .crashed
            state.lastError = error.localizedDescription
        }
        recomputeAggregate()
    }

    func stop(_ id: String) {
        guard let state = services.first(where: { $0.id == id }) else { return }
        if id == BackendServiceSpec.aiServiceID, !isAIServicePaused {
            aiShouldResumeAfterPause = false
        }
        state.status = .stopped
        if let p = processes[id] {
            if p.isRunning { p.terminate() }
            processes.removeValue(forKey: id)
        }
        stdoutPipes[id]?.fileHandleForReading.readabilityHandler = nil
        stdoutPipes.removeValue(forKey: id)
        state.pid = nil
        processMetrics[id] = nil
        if services.allSatisfy({ $0.pid == nil }) {
            stopHealthLoop()
            stopMetricsLoop()
        }
        recomputeAggregate()
    }

    func waitForHealthy(_ id: String, timeout: TimeInterval = 60) async -> Bool {
        guard let state = services.first(where: { $0.id == id }) else { return false }
        let spec = state.spec
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if state.status == .healthy { return true }
            if state.status == .stopped || state.status == .crashed {
                return false
            }
            let healthy = await Self.probe(spec: spec)
            state.lastHealthCheck = Date()
            if healthy {
                state.status = .healthy
                recomputeAggregate()
                return true
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        return false
    }

    func restart(_ id: String) {
        stop(id)
        // Give the OS a beat to release the port.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.services.first(where: { $0.id == id })?.restartCount += 1
            self?.start(id)
        }
    }

    func restartCrashed() {
        for s in services where s.status == .crashed { restart(s.id) }
    }

    @discardableResult
    func applyStoredAIModelProfile(restartIfRunning: Bool = false) -> LocalAIModelProfile {
        let raw = UserDefaults.standard.string(forKey: "ai.modelProfile") ?? LocalAIModelProfile.singleE4B.rawValue
        let profile = LocalAIModelProfile(rawValue: raw) ?? .singleE4B
        writeAIModelProfile(profile)
        if restartIfRunning,
           services.first(where: { $0.id == BackendServiceSpec.aiServiceID })?.pid != nil {
            restart(BackendServiceSpec.aiServiceID)
        }
        return profile
    }

    func setManualAIPowerSavingMode(_ enabled: Bool) {
        isManualAIPowerSavingModeEnabled = enabled
        if enabled {
            pauseAIService()
        } else {
            resumeAIServiceIfPauseCleared()
        }
    }

    private func writeAIModelProfile(_ profile: LocalAIModelProfile) {
        let configURL = backendDir.appendingPathComponent("dual_config.json")
        var config: [String: Any] = [:]
        if let data = try? Data(contentsOf: configURL),
           let object = try? JSONSerialization.jsonObject(with: data),
           let dictionary = object as? [String: Any] {
            config = dictionary
        }
        config["enabled"] = false
        config["runtime_profile"] = profile.rawValue
        config["local_model"] = profile.runtimeModel
        config["parallel"] = [
            "enabled": profile.parallelWorkers > 1,
            "model": profile.runtimeModel,
            "workers": profile.parallelWorkers,
        ]

        do {
            let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: configURL, options: .atomic)
        } catch {
            services.first(where: { $0.id == BackendServiceSpec.aiServiceID })?.lastError = "AI profile write failed: \(error.localizedDescription)"
        }
    }

    @objc private func handleTerminate() { stopAll() }

    @objc private func handlePowerStateDidChange() {
        updatePowerSavingPauseState()
    }

    @objc private func handleWillSleep() {
        pauseAIServiceForPowerSaving()
    }

    @objc private func handleDidWake() {
        updatePowerSavingPauseState()
    }

    private static let powerSavingPauseReason = "後台電腦已進入省電模式"
    private static let manualPowerSavingPauseReason = "已手動啟用省電模式"

    private var currentAIServicePauseReason: String? {
        if isAIServicePausedForPowerSaving { return Self.powerSavingPauseReason }
        if isManualAIPowerSavingModeEnabled { return Self.manualPowerSavingPauseReason }
        return nil
    }

    private func updatePowerSavingPauseState() {
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            pauseAIServiceForPowerSaving()
        } else {
            resumeAIServiceAfterPowerSavingIfNeeded()
        }
    }

    private func pauseAIServiceForPowerSaving() {
        isAIServicePausedForPowerSaving = true
        pauseAIService()
    }

    private func pauseAIService() {
        guard let state = services.first(where: { $0.id == BackendServiceSpec.aiServiceID }) else { return }
        if state.pid != nil || state.status == .starting || state.status == .healthy || state.status == .unhealthy {
            aiShouldResumeAfterPause = true
        }
        aiServicePauseReason = currentAIServicePauseReason
        stop(BackendServiceSpec.aiServiceID)
        state.lastError = currentAIServicePauseReason
    }

    private func resumeAIServiceAfterPowerSavingIfNeeded() {
        isAIServicePausedForPowerSaving = false
        resumeAIServiceIfPauseCleared()
    }

    private func resumeAIServiceIfPauseCleared() {
        if isAIServicePaused {
            aiServicePauseReason = currentAIServicePauseReason
            services.first(where: { $0.id == BackendServiceSpec.aiServiceID })?.lastError = currentAIServicePauseReason
            return
        }
        let shouldResume = aiShouldResumeAfterPause
        aiShouldResumeAfterPause = false
        aiServicePauseReason = nil
        services.first(where: { $0.id == BackendServiceSpec.aiServiceID })?.lastError = nil
        guard shouldResume else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.start(BackendServiceSpec.aiServiceID)
        }
    }

    // MARK: - Health probing

    private func startHealthLoop() {
        guard healthTimer == nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.probeAll() }
        }
        timer.tolerance = 5.0
        healthTimer = timer
    }

    private func stopHealthLoop() {
        healthTimer?.invalidate()
        healthTimer = nil
    }

    private func probeAll() {
        for state in services where state.status != .stopped {
            Task.detached { [weak self, spec = state.spec] in
                let healthy = await Self.probe(spec: spec)
                await MainActor.run { [weak self, weak state] in
                    guard let state else { return }
                    state.lastHealthCheck = Date()
                    if state.status == .stopped { return }
                    state.status = healthy ? .healthy : .unhealthy
                    self?.recomputeAggregate()
                }
            }
        }
    }

    private static func probe(spec: BackendServiceSpec) async -> Bool {
        if spec.isHTTP {
            guard let url = URL(string: "http://127.0.0.1:\(spec.port)/health") else { return false }
            var req = URLRequest(url: url)
            req.timeoutInterval = 2
            do {
                let (_, resp) = try await URLSession.shared.data(for: req)
                if let http = resp as? HTTPURLResponse { return (200..<300).contains(http.statusCode) }
                return false
            } catch { return false }
        } else {
            return await tcpProbe(host: "127.0.0.1", port: spec.port, timeout: 2)
        }
    }

    private static func tcpProbe(host: String, port: Int, timeout: TimeInterval) async -> Bool {
        await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            let queue = DispatchQueue.global(qos: .utility)
            queue.async {
                let sock = socket(AF_INET, SOCK_STREAM, 0)
                guard sock >= 0 else { cont.resume(returning: false); return }
                var addr = sockaddr_in()
                addr.sin_family = sa_family_t(AF_INET)
                addr.sin_port = in_port_t(UInt16(port).bigEndian)
                addr.sin_addr.s_addr = inet_addr(host)
                let result = withUnsafePointer(to: &addr) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        connect(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
                close(sock)
                cont.resume(returning: result == 0)
            }
        }
    }

    private func recomputeAggregate() {
        let active = services.filter { $0.status != .stopped }
        allHealthy = !active.isEmpty && active.allSatisfy { $0.status == .healthy }
        anyCrashed = services.contains { $0.status == .crashed }
    }

    private func startMetricsLoop() {
        guard metricsTimer == nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshProcessMetrics() }
        }
        timer.tolerance = 10.0
        metricsTimer = timer
        refreshProcessMetrics()
    }

    private func stopMetricsLoop() {
        metricsTimer?.invalidate()
        metricsTimer = nil
        processMetrics.removeAll()
    }

    private func refreshProcessMetrics() {
        let active = services.compactMap { state -> (id: String, pid: Int32)? in
            guard let pid = state.pid else { return nil }
            return (state.id, pid)
        }
        guard !active.isEmpty else {
            stopMetricsLoop()
            return
        }

        Task.detached { [active] in
            let collected = active.reduce(into: [String: BackendProcessMetrics]()) { result, item in
                result[item.id] = Self.collectMetrics(pid: item.pid)
            }
            await MainActor.run { [weak self, collected] in
                guard let self else { return }
                self.processMetrics = collected
            }
        }
    }

    // MARK: - Process metrics (best-effort, optional UI use)

    /// Returns ("12.3", "456") for (cpu%, rss-MB) by shelling out to `ps`.
    /// Empty strings if PID unknown or `ps` fails.
    func metrics(for id: String) -> BackendProcessMetrics {
        processMetrics[id] ?? .empty
    }

    nonisolated private static func collectMetrics(pid: Int32) -> BackendProcessMetrics {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/ps")
        p.arguments = ["-o", "%cpu=,rss=", "-p", "\(pid)"]
        let pipe = Pipe()
        p.standardOutput = pipe
        do {
            try p.run()
            p.waitUntilExit()
            let out = (String(data: pipe.fileHandleForReading.readDataToEndOfFile(),
                              encoding: .utf8) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = out.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 2,
                  let rssKB = Int(parts[1]) else {
                return BackendProcessMetrics(cpu: String(parts.first ?? ""), memMB: "")
            }
            let rssMB = rssKB / 1024
            return BackendProcessMetrics(cpu: String(parts[0]), memMB: String(rssMB))
        } catch {
            return .empty
        }
    }
}

#else  // iOS / iPadOS stub — HQ on iPad does not host the Python backend.

@MainActor
final class BackendSupervisor: ObservableObject {
    @Published var services: [BackendServiceState] = []
    @Published var allHealthy: Bool = false
    @Published var anyCrashed: Bool = false
    @Published var isAIServicePausedForPowerSaving: Bool = false
    @Published var isManualAIPowerSavingModeEnabled: Bool = false
    @Published var aiServicePauseReason: String? = nil
    var isAIServicePaused: Bool { false }
    func startAll() {}
    func startEnergyEfficientServices() {}
    func stopAll() {}
    func start(_ id: String) {}
    func stop(_ id: String) {}
    func restart(_ id: String) {}
    func restartCrashed() {}
    func startAIServiceIfNeeded() {}
    func startPythonWhisperIfNeeded() {}
    func waitForHealthy(_ id: String, timeout: TimeInterval = 60) async -> Bool { false }
    func setManualAIPowerSavingMode(_ enabled: Bool) {}
    func metrics(for id: String) -> BackendProcessMetrics { .empty }
}

@MainActor
final class BackendServiceState: ObservableObject, Identifiable {
    let spec: BackendServiceSpec = .init(id: "stub", displayName: "Stub",
                                          scriptName: "", port: 0,
                                          isHTTP: false, startDelay: 0)
    var id: String { spec.id }
    @Published var status: BackendServiceStatus = .stopped
    @Published var pid: Int32? = nil
    @Published var restartCount: Int = 0
    @Published var lastError: String? = nil
    @Published var logTail: [String] = []
    @Published var startedAt: Date? = nil
    @Published var lastHealthCheck: Date? = nil
}

#endif
