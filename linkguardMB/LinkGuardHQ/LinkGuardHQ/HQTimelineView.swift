import SwiftUI

struct HQTimelineView: View {
    @ObservedObject var vm: HQViewModel
    @State private var selectedFilter: TimelineEventType? = nil

    private var filteredEvents: [TimelineEvent] {
        guard let filter = selectedFilter else { return vm.timelineEvents }
        return vm.timelineEvents.filter { $0.eventType == filter }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 篩選列
            filterBar
                .padding(.horizontal)
                .padding(.vertical, 8)

            Divider()

            // 事件列表
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if filteredEvents.isEmpty {
                        emptyState
                    } else {
                        ForEach(filteredEvents) { event in
                            TimelineEventCard(event: event)
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
        }
        .navigationTitle(L("事件日誌"))
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    vm.clearTimeline()
                } label: {
                    Label(L("清除日誌"), systemImage: "trash")
                }
                .disabled(vm.timelineEvents.isEmpty)
                .help(L("清除所有日誌"))
            }
        }
    }

    // MARK: - 篩選列

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                FilterChip(label: "全部", isSelected: selectedFilter == nil) {
                    selectedFilter = nil
                }
                ForEach(TimelineEventType.allCases, id: \.self) { type in
                    FilterChip(
                        label: type.rawValue,
                        icon: type.icon,
                        color: type.color,
                        isSelected: selectedFilter == type
                    ) {
                        selectedFilter = type
                    }
                }
            }
        }
    }

    // MARK: - 空狀態

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 40)).foregroundColor(.secondary)
            Text(L("尚無事件記錄"))
                .foregroundColor(.secondary)
            Text(L("系統操作將自動記錄在此"))
                .font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - 篩選 Chip

struct FilterChip: View {
    let label: String
    var icon: String? = nil
    var color: Color = .accentColor
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon).font(.caption2)
                }
                Text(label).font(.caption).bold()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? color.opacity(0.2) : Color.clear)
            .foregroundColor(isSelected ? color : .secondary)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? color : Color.secondary.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 事件卡片

struct TimelineEventCard: View {
    let event: TimelineEvent

    var body: some View {
        HStack(spacing: 12) {
            // 左側色條 + 圖示
            VStack(spacing: 0) {
                Image(systemName: event.eventType.icon)
                    .font(.body)
                    .foregroundColor(event.eventType.color)
                    .frame(width: 32, height: 32)
                    .background(event.eventType.color.opacity(0.15))
                    .cornerRadius(8)
            }

            // 內容
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(event.title)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    Text(event.relativeTimeText)
                        .font(.caption2).foregroundColor(.secondary)
                }
                if !event.detail.isEmpty {
                    Text(event.detail)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                HStack(spacing: 6) {
                    Text(L(event.eventType.rawValue))
                        .font(.caption2).bold()
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(event.eventType.color.opacity(0.15))
                        .foregroundColor(event.eventType.color)
                        .cornerRadius(4)
                    Text(event.source)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(event.timeText)
                        .font(.caption2).foregroundColor(.secondary)
                }
            }
        }
        .padding(NV.cardPadding)
        .background(.regularMaterial)
        .cornerRadius(NV.cardRadius)
    }
}
