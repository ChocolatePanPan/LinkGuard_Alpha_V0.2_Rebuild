import SwiftUI

struct ContentView: View {

    @EnvironmentObject var engine: CommandEngine
    @State private var alarmActive = false
    @State private var showingAlert = false
    @State private var alertMessage = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {

                // MARK: Header
                VStack(spacing: 8) {
                    Image(systemName: "shield.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(alarmActive ? .red : .blue)
                        .symbolEffect(.pulse, isActive: alarmActive)

                    Text("LinkGuard")
                        .font(.largeTitle.bold())

                    Text(alarmActive ? "⚠️ ALARM ACTIVE" : "Network Protected")
                        .font(.subheadline)
                        .foregroundStyle(alarmActive ? .red : .secondary)
                }
                .padding(.top)

                Divider()

                // MARK: Action Buttons
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {

                    ActionButton(
                        title: "Scan Network",
                        icon: "network",
                        color: .blue
                    ) {
                        runCommand(.init(type: .scanNetwork))
                    }

                    ActionButton(
                        title: alarmActive ? "Stop Alarm" : "Test Alarm",
                        icon: alarmActive ? "bell.slash.fill" : "bell.fill",
                        color: alarmActive ? .orange : .red
                    ) {
                        toggleAlarm()
                    }

                    ActionButton(
                        title: "Notifications",
                        icon: "app.badge",
                        color: .purple
                    ) {
                        sendTestNotification()
                    }

                    ActionButton(
                        title: "Generate Report",
                        icon: "doc.text",
                        color: .green
                    ) {
                        runCommand(.init(type: .generateReport))
                    }
                }
                .padding(.horizontal)

                Divider()

                // MARK: Command History
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Command History")
                            .font(.headline)
                        Spacer()
                        if !engine.commandHistory.isEmpty {
                            Button("Clear") {
                                engine.clearHistory()
                            }
                            .font(.caption)
                        }
                    }

                    if engine.commandHistory.isEmpty {
                        Text("No commands executed yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding()
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 6) {
                                ForEach(engine.commandHistory.reversed()) { result in
                                    HistoryRow(result: result)
                                }
                            }
                        }
                        .frame(maxHeight: 200)
                    }
                }
                .padding(.horizontal)

                Spacer()
            }
            .navigationTitle("LinkGuard")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
        }
        .alert("LinkGuard", isPresented: $showingAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }

    // MARK: - Actions

    private func runCommand(_ command: Command) {
        engine.execute(command) { result in
            alertMessage = result.message
            showingAlert = true
        }
    }

    private func toggleAlarm() {
        if alarmActive {
            AlarmPlayer.shared.stopAlarm()
            alarmActive = false
        } else {
            AlarmPlayer.shared.startAlarm()
            alarmActive = true
        }
    }

    private func sendTestNotification() {
        NotificationManager.shared.scheduleNotification(
            title: "LinkGuard Test",
            body: "This is a test notification from LinkGuard.",
            category: .info
        )
        alertMessage = "Test notification scheduled."
        showingAlert = true
    }
}

// MARK: - Supporting Views

struct ActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                Text(title)
                    .font(.caption.bold())
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(color.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct HistoryRow: View {
    let result: CommandResult

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(result.success ? .green : .red)
                .font(.caption)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(result.command.type.displayName)
                    .font(.caption.bold())
                Text(result.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    ContentView()
        .environmentObject(CommandEngine.shared)
}
