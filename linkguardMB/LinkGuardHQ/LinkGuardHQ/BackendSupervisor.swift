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
    let id: String              // canonical key, e.g. "gemma4_server"
    let displayName: String     // shown in UI
    let scriptName: String      // file under backend dir, e.g. "gemma4_server.py"
    let port: Int               // primary port (for health probe / display)
    let isHTTP: Bool            // true → probe via /health; false → TCP connect
    let startDelay: TimeInterval // pre-launch delay, mirrors macos/start_all.sh

    /// Mac HQ already owns 8003 (speech), 8005 (LGAP audio), and 9001 (UDP audio).
    /// Keep the embedded Python sidecar to services that do not collide with those
    /// native HQ listeners while still covering AI, TCP bridge, resources, photos,
    /// MQTT/LoRa, and optional Python Whisper.
    static let all: [BackendServiceSpec] = [
        .init(id: "mqtt_broker",    displayName: "MQTT Client",        scriptName: "mqtt_broker.py",    port: 1883, isHTTP: false, startDelay: 0),
        .init(id: "tcp_server",     displayName: "TCP Aggregator",     scriptName: "tcp_server.py",     port: 9000, isHTTP: false, startDelay: 0),
        .init(id: "gemma4_server",  displayName: "Gemma4 AI",          scriptName: "gemma4_server.py",  port: 8001, isHTTP: true,  startDelay: 2),
        .init(id: "whisper_server", displayName: "Whisper Voice",      scriptName: "whisper_server.py", port: 8002, isHTTP: true,  startDelay: 0),
        .init(id: "photo_server",   displayName: "Photo Server",       scriptName: "photo_server.py",   port: 8004, isHTTP: true,  startDelay: 2),
        .init(id: "resource_server",displayName: "Resource Server",    scriptName: "resource_server.py",port: 8006, isHTTP: true,  startDelay: 0),
    ]
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

    fileprivate func appendLog(_ line: String) {
        logTail.append(line)
        if logTail.count > 200 { logTail.removeFirst(logTail.count - 200) }
    }
}

// MARK: - Supervisor

@MainActor
final class BackendSupervisor: ObservableObject {

    /// Where to find the Python scripts. On a packaged build this is
    /// `~/Library/Application Support/LinkGuardHQ/backend`. In a dev build
    /// running from Xcode, it falls back to the repository `macos/` folder if
    /// `~/Library/...` doesn't exist yet.
    @Published var backendDir: URL
    @Published var pythonExecutable: URL?
    @Published var services: [BackendServiceState]
    @Published var allHealthy: Bool = false
    @Published var anyCrashed: Bool = false
    @Published private var processMetrics: [String: BackendProcessMetrics] = [:]

    private var processes: [String: Process] = [:]
    private var stdoutPipes: [String: Pipe] = [:]
    private var healthTimer: Timer?
    private var metricsTimer: Timer?

    init() {
        self.services = BackendServiceSpec.all.map { BackendServiceState(spec: $0) }
        self.backendDir = Self.resolveBackendDir()
        self.pythonExecutable = Self.resolvePython(under: backendDir)
        // Cleanly stop child processes when the app is terminating.
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleTerminate),
            name: NSApplication.willTerminateNotification, object: nil
        )
    }

    deinit {
        // Best effort, can't await on MainActor here.
        for p in processes.values where p.isRunning { p.terminate() }
    }

    // MARK: - Path resolution

    /// Preferred layout: bundled `backend/` resource → copied on first launch
    /// to `~/Library/Application Support/LinkGuardHQ/backend/`.
    static func resolveBackendDir() -> URL {
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
        Task {
            for spec in BackendServiceSpec.all {
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
        for spec in BackendServiceSpec.all { stop(spec.id) }
        stopHealthLoop()
        stopMetricsLoop()
    }

    func start(_ id: String) {
        guard let state = services.first(where: { $0.id == id }) else { return }
        guard state.status != .starting && state.status != .healthy else { return }
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

        // Forward stdout & stderr into the per-service ring buffer.
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak state] handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor [weak state] in
                guard let state else { return }
                for line in chunk.split(whereSeparator: \.isNewline) {
                    state.appendLog(String(line))
                }
            }
        }

        p.terminationHandler = { [weak self, weak state] proc in
            Task { @MainActor [weak self, weak state] in
                guard let self, let state else { return }
                let code = proc.terminationStatus
                if state.status != .stopped {
                    state.status = .crashed
                    state.lastError = "exited with code \(code)"
                    self.recomputeAggregate()
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
            startMetricsLoop()
        } catch {
            state.status = .crashed
            state.lastError = error.localizedDescription
        }
        recomputeAggregate()
    }

    func stop(_ id: String) {
        guard let state = services.first(where: { $0.id == id }) else { return }
        state.status = .stopped
        if let p = processes[id] {
            if p.isRunning { p.terminate() }
            processes.removeValue(forKey: id)
        }
        stdoutPipes[id]?.fileHandleForReading.readabilityHandler = nil
        stdoutPipes.removeValue(forKey: id)
        state.pid = nil
        processMetrics[id] = nil
        if services.allSatisfy({ $0.pid == nil }) { stopMetricsLoop() }
        recomputeAggregate()
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

    @objc private func handleTerminate() { stopAll() }

    // MARK: - Health probing

    private func startHealthLoop() {
        guard healthTimer == nil else { return }
        healthTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.probeAll() }
        }
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
        metricsTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshProcessMetrics() }
        }
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
    func startAll() {}
    func stopAll() {}
    func start(_ id: String) {}
    func stop(_ id: String) {}
    func restart(_ id: String) {}
    func restartCrashed() {}
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
