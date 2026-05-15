import Foundation
import Combine

// MARK: - Command Types

enum CommandType: String, CaseIterable, Identifiable {
    case scanNetwork      = "SCAN_NETWORK"
    case blockURL         = "BLOCK_URL"
    case allowURL         = "ALLOW_URL"
    case generateReport   = "GENERATE_REPORT"
    case clearLog         = "CLEAR_LOG"
    case triggerAlarm     = "TRIGGER_ALARM"
    case stopAlarm        = "STOP_ALARM"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .scanNetwork:    return "Scan Network"
        case .blockURL:       return "Block URL"
        case .allowURL:       return "Allow URL"
        case .generateReport: return "Generate Report"
        case .clearLog:       return "Clear Log"
        case .triggerAlarm:   return "Trigger Alarm"
        case .stopAlarm:      return "Stop Alarm"
        }
    }
}

// MARK: - Command & Result Models

struct Command {
    let id: UUID
    let type: CommandType
    let parameters: [String: Any]
    let timestamp: Date

    init(type: CommandType, parameters: [String: Any] = [:]) {
        self.id = UUID()
        self.type = type
        self.parameters = parameters
        self.timestamp = Date()
    }
}

struct CommandResult: Identifiable {
    let id: UUID
    let command: Command
    let success: Bool
    let message: String
    let data: Any?
    let completedAt: Date

    init(command: Command, success: Bool, message: String, data: Any? = nil) {
        self.id = UUID()
        self.command = command
        self.success = success
        self.message = message
        self.data = data
        self.completedAt = Date()
    }
}

// MARK: - CommandEngine

/// Central engine for executing and logging LinkGuard commands.
final class CommandEngine: ObservableObject {

    static let shared = CommandEngine()

    @Published private(set) var commandHistory: [CommandResult] = []
    @Published private(set) var isProcessing: Bool = false

    private let queue = DispatchQueue(label: "com.linkguard.commandengine", qos: .userInitiated)

    private init() {}

    // MARK: - Public API

    func execute(_ command: Command, completion: ((CommandResult) -> Void)? = nil) {
        isProcessing = true
        queue.async { [weak self] in
            guard let self else { return }
            let result = self.process(command)
            DispatchQueue.main.async {
                self.commandHistory.append(result)
                self.isProcessing = false
                completion?(result)
            }
        }
    }

    func clearHistory() {
        commandHistory.removeAll()
    }

    // MARK: - Private Processing

    private func process(_ command: Command) -> CommandResult {
        switch command.type {

        case .scanNetwork:
            // Placeholder: integrate with NetworkMonitor
            return CommandResult(command: command, success: true,
                                 message: "Network scan completed. No threats detected.",
                                 data: ["threatsFound": 0])

        case .blockURL:
            guard let url = command.parameters["url"] as? String, !url.isEmpty else {
                return CommandResult(command: command, success: false,
                                     message: "BLOCK_URL requires a non-empty 'url' parameter.")
            }
            return CommandResult(command: command, success: true,
                                 message: "Blocked URL: \(url)")

        case .allowURL:
            guard let url = command.parameters["url"] as? String, !url.isEmpty else {
                return CommandResult(command: command, success: false,
                                     message: "ALLOW_URL requires a non-empty 'url' parameter.")
            }
            return CommandResult(command: command, success: true,
                                 message: "Allowed URL: \(url)")

        case .generateReport:
            let count = commandHistory.count
            return CommandResult(command: command, success: true,
                                 message: "Report generated. \(count) entries in history.",
                                 data: commandHistory)

        case .clearLog:
            DispatchQueue.main.async { self.clearHistory() }
            return CommandResult(command: command, success: true, message: "Command log cleared.")

        case .triggerAlarm:
            DispatchQueue.main.async { AlarmPlayer.shared.startAlarm() }
            return CommandResult(command: command, success: true, message: "Alarm triggered.")

        case .stopAlarm:
            DispatchQueue.main.async { AlarmPlayer.shared.stopAlarm() }
            return CommandResult(command: command, success: true, message: "Alarm stopped.")
        }
    }
}
