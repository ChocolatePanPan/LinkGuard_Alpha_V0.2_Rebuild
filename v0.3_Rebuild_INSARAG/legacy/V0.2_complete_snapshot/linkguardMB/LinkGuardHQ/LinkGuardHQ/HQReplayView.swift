import SwiftUI

// MARK: - 主頁面

struct HQReplayView: View {
    @StateObject private var replayVM = HQReplayViewModel()

    var body: some View {
        if replayVM.isLoaded {
            replayContent
        } else {
            landingView
        }
    }

    // MARK: - 落地頁（選擇 DB）

    private var landingView: some View {
        VStack(spacing: 24) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 64))
                .foregroundColor(NV.info)

            Text("事件回放")
                .font(.largeTitle.bold())

            Text("選擇一個 linkguard.db 資料庫檔案\n開始離線回放歷史任務資料")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            if let err = replayVM.loadError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(NV.danger)
                    Text(err)
                        .font(.callout)
                        .foregroundColor(NV.danger)
                }
                .padding()
                .background(NV.danger.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: NV.cardRadius))
            }

            Button {
                replayVM.openFilePicker()
            } label: {
                Label("開啟資料庫檔案…", systemImage: "folder.badge.plus")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(NV.info)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 回放主介面

    private var replayContent: some View {
        VStack(spacing: 0) {
            topBar
            Divider().background(NV.greenDim)
            HStack(spacing: 0) {
                leftPanel
                Divider().background(NV.greenDim)
                centerPanel
                Divider().background(NV.greenDim)
                rightPanel
            }
            Divider().background(NV.greenDim)
            eventAxis
        }
        .background(NV.nightVisionBG.ignoresSafeArea())
    }

    // MARK: - 頂部控制列

    private var topBar: some View {
        HStack(spacing: 12) {
            // 返回按鈕
            Button {
                replayVM.pause()
                replayVM.isLoaded = false
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)
            .help("關閉回放，重新選擇檔案")

            Divider().frame(height: 20)

            // 播放控制
            Button { replayVM.seekToStart() } label: {
                Image(systemName: "backward.end.fill")
            }
            .buttonStyle(.plain)
            .help("跳到開始")

            Button {
                if replayVM.isPlaying { replayVM.pause() }
                else { replayVM.play() }
            } label: {
                Image(systemName: replayVM.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 20)
            }
            .buttonStyle(.plain)
            .help(replayVM.isPlaying ? "暫停" : "播放")

            Button { replayVM.seekToEnd() } label: {
                Image(systemName: "forward.end.fill")
            }
            .buttonStyle(.plain)
            .help("跳到結束")

            Divider().frame(height: 20)

            // 時間軸 slider
            Slider(value: Binding(
                get: { replayVM.sliderValue },
                set: { v in
                    replayVM.pause()
                    replayVM.sliderValue = v
                    replayVM.onSliderChanged(v)
                }
            ), in: 0...1)
            .accentColor(NV.info)
            .frame(maxWidth: .infinity)

            // 當前時間顯示
            Text(timeDisplay)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(NV.info)
                .frame(minWidth: 180, alignment: .leading)

            Divider().frame(height: 20)

            // 速度選擇
            HStack(spacing: 4) {
                ForEach([1.0, 2.0, 4.0, 8.0], id: \.self) { spd in
                    Button {
                        replayVM.playbackSpeed = spd
                    } label: {
                        Text(spd == 1 ? "1×" : spd == 2 ? "2×" : spd == 4 ? "4×" : "8×")
                            .font(.caption.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(replayVM.playbackSpeed == spd ? NV.info : Color.clear)
                            .foregroundColor(replayVM.playbackSpeed == spd ? .black : NV.info)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider().frame(height: 20)

            // 換檔按鈕
            Button {
                replayVM.pause()
                replayVM.openFilePicker()
            } label: {
                Label("換檔", systemImage: "folder")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(NV.nightVisionChrome)
    }

    private var timeDisplay: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy/MM/dd HH:mm:ss"
        fmt.locale = Locale(identifier: "zh-Hant_TW")
        fmt.timeZone = TimeZone(identifier: "Asia/Taipei")
        return fmt.string(from: replayVM.currentTime)
    }

    // MARK: - 左側面板：傷員 + 節點

    private var leftPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // 傷員
                sectionHeader("傷員列表", icon: "person.fill.questionmark", color: NV.danger)
                if replayVM.snapshot.patients.isEmpty {
                    emptyHint("此時間點尚無傷員記錄")
                } else {
                    ForEach(replayVM.snapshot.patients.sorted {
                        priorityRank($0.priority) < priorityRank($1.priority)
                    }) { patient in
                        patientCard(patient)
                    }
                }

                Divider().background(NV.greenDim).padding(.vertical, 4)

                // LoRa 節點
                sectionHeader("LoRa 節點", icon: "antenna.radiowaves.left.and.right", color: NV.info)
                if replayVM.snapshot.nodes.isEmpty {
                    emptyHint("此時間點尚無節點記錄")
                } else {
                    ForEach(replayVM.snapshot.nodes) { node in
                        nodeCard(node)
                    }
                }

                Divider().background(NV.greenDim).padding(.vertical, 4)

                // 氣象
                sectionHeader("氣象資料", icon: "cloud.sun.fill", color: NV.team)
                weatherCard
            }
            .padding(12)
        }
        .frame(width: 240)
        .background(NV.nightVisionChrome)
    }

    // MARK: - 中央面板：最近事件串流

    private var centerPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "list.bullet.timeline")
                    .foregroundColor(NV.info)
                Text("事件串流")
                    .font(.headline.bold())
                    .foregroundColor(NV.info)
                Spacer()
                Text("\(replayVM.snapshot.recentEvents.count) 筆")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider().background(NV.greenDim)

            if replayVM.snapshot.recentEvents.isEmpty {
                Spacer()
                emptyHint("尚無事件")
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(replayVM.snapshot.recentEvents) { ev in
                            eventRow(ev)
                        }
                    }
                    .padding(12)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 右側面板：決策

    private var rightPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("最新指揮決策", icon: "brain.head.profile", color: NV.command)
                if let d = replayVM.snapshot.latestDecision {
                    decisionCard(d)
                } else {
                    emptyHint("此時間點尚無決策記錄")
                }
            }
            .padding(12)
        }
        .frame(width: 300)
        .background(NV.nightVisionChrome)
    }

    // MARK: - 底部事件軸

    private var eventAxis: some View {
        Canvas { ctx, size in
            guard !replayVM.allEvents.isEmpty,
                  let start = replayVM.timelineStart,
                  let end = replayVM.timelineEnd,
                  end > start else { return }

            let range = end.timeIntervalSince(start)
            let pad: CGFloat = 20
            let w = size.width - pad * 2

            // 背景線
            ctx.stroke(
                Path { p in p.move(to: CGPoint(x: pad, y: 20)); p.addLine(to: CGPoint(x: pad + w, y: 20)) },
                with: .color(NV.greenDim), lineWidth: 1
            )

            let typeColors: [String: Color] = [
                "decision": NV.info, "patient": NV.danger,
                "report": NV.warning, "node": NV.green, "weather": NV.team
            ]

            // 事件點
            for ev in replayVM.allEvents {
                let t = ev.timestamp.timeIntervalSince(start)
                let x = pad + CGFloat(t / range) * w
                let col = typeColors[ev.type] ?? .gray
                ctx.fill(
                    Path(ellipseIn: CGRect(x: x - 3, y: 14, width: 6, height: 6)),
                    with: .color(col)
                )
            }

            // 當前時間指示線
            let ct = replayVM.currentTime.timeIntervalSince(start)
            let cx = pad + CGFloat(max(0, min(1, ct / range))) * w
            ctx.stroke(
                Path { p in p.move(to: CGPoint(x: cx, y: 4)); p.addLine(to: CGPoint(x: cx, y: 54)) },
                with: .color(NV.info), lineWidth: 2
            )
        }
        .frame(height: 58)
        .background(NV.nightVisionChrome)
        .onTapGesture { location in
            guard let start = replayVM.timelineStart,
                  let end = replayVM.timelineEnd, end > start else { return }
            // Canvas width 無法直接取得，用 GeometryReader 替代
        }
    }

    // MARK: - 子元件

    private func sectionHeader(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundColor(color).font(.caption)
            Text(title).font(.caption.bold()).foregroundColor(color)
        }
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.vertical, 4)
    }

    private func patientCard(_ p: ReplayPatient) -> some View {
        let (bg, bar) = priorityColors(p.priority)
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(p.id).font(.caption.bold()).foregroundColor(.primary)
                Spacer()
                priorityTag(p.priority)
            }
            if !p.locationDesc.isEmpty {
                Text(p.locationDesc).font(.caption2).foregroundColor(.secondary)
            }
            if !p.reason.isEmpty {
                Text(p.reason).font(.caption2).foregroundColor(.secondary).lineLimit(1)
            }
        }
        .padding(8)
        .background(bg)
        .overlay(Rectangle().frame(width: 3).foregroundColor(bar), alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func priorityTag(_ priority: String) -> some View {
        let (_, bar) = priorityColors(priority)
        return Text(priority)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(bar.opacity(0.2))
            .foregroundColor(bar)
            .clipShape(Capsule())
    }

    private func priorityColors(_ priority: String) -> (Color, Color) {
        switch priority {
        case "紅色": return (NV.danger.opacity(0.12), NV.danger)
        case "黑色": return (Color.gray.opacity(0.12), Color.gray)
        case "黃色": return (NV.warning.opacity(0.12), NV.warning)
        default:     return (NV.green.opacity(0.10), NV.green)
        }
    }

    private func priorityRank(_ priority: String) -> Int {
        switch priority {
        case "紅色": return 0
        case "黑色": return 1
        case "黃色": return 2
        default:     return 3
        }
    }

    private func nodeCard(_ n: ReplayNode) -> some View {
        HStack(spacing: 8) {
            Circle().fill(n.online ? NV.info : NV.danger).frame(width: 6, height: 6)
            Text(n.id).font(.caption.bold()).foregroundColor(.primary)
            Spacer()
            Text("🔋\(n.battery)%")
                .font(.caption2).foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(NV.info.opacity(0.08))
        .overlay(Rectangle().frame(width: 3).foregroundColor(n.online ? NV.info : NV.danger), alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private var weatherCard: some View {
        if let w = replayVM.snapshot.weather {
            VStack(alignment: .leading, spacing: 4) {
                weatherRow("🌡️ 氣溫", value: "\(Int(w.temperature)) °C")
                weatherRow("💧 濕度", value: "\(Int(w.humidity)) %")
                weatherRow("💨 風速", value: String(format: "%.1f m/s", w.windSpeed))
                weatherRow("🌧️ 雨量", value: String(format: "%.1f mm", w.rainfall))
            }
            .padding(8)
            .background(NV.team.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            emptyHint("無氣象資料")
        }
    }

    private func weatherRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundColor(.secondary)
            Spacer()
            Text(value).font(.caption.bold()).foregroundColor(NV.team)
        }
    }

    private func eventRow(_ ev: ReplayTimelineEvent) -> some View {
        let typeColors: [String: Color] = [
            "decision": NV.info, "patient": NV.danger,
            "report": NV.warning, "node": NV.green, "weather": NV.team
        ]
        let typeIcons: [String: String] = [
            "decision": "brain.head.profile",
            "patient": "person.fill.questionmark",
            "report": "doc.text.fill",
            "node": "antenna.radiowaves.left.and.right",
            "weather": "cloud.fill"
        ]
        let color = typeColors[ev.type] ?? .gray
        let icon = typeIcons[ev.type] ?? "circle"

        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "HH:mm:ss"
        timeFmt.timeZone = TimeZone(identifier: "Asia/Taipei")

        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(color)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(ev.summary)
                    .font(.caption)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                Text(timeFmt.string(from: ev.timestamp))
                    .font(.caption2.monospaced())
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(color.opacity(0.05))
        .overlay(Rectangle().frame(width: 2).foregroundColor(color), alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func decisionCard(_ d: ReplayDecision) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(d.triggerType.isEmpty ? "決策" : d.triggerType)
                    .font(.caption2.bold())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(NV.command.opacity(0.15))
                    .foregroundColor(NV.command)
                    .clipShape(Capsule())
                Spacer()
                Text(shortTime(d.timestamp))
                    .font(.caption2.monospaced())
                    .foregroundColor(.secondary)
            }
            Text(d.decisionText)
                .font(.caption)
                .foregroundColor(.primary)
                .lineSpacing(3)
        }
        .padding(10)
        .background(NV.command.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: NV.cardRadius)
                .stroke(NV.command.opacity(0.25), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: NV.cardRadius))
    }

    private func shortTime(_ iso: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        f.timeZone = TimeZone(identifier: "Asia/Taipei")
        let parsers = [
            ISO8601DateFormatter(),
            { () -> DateFormatter in
                let ff = DateFormatter()
                ff.dateFormat = "yyyy-MM-dd HH:mm:ss"
                ff.locale = Locale(identifier: "en_US_POSIX")
                return ff
            }()
        ]
        for parser in parsers {
            if let d = (parser as? ISO8601DateFormatter)?.date(from: iso) {
                return f.string(from: d)
            }
            if let df = parser as? DateFormatter, let d = df.date(from: iso) {
                return f.string(from: d)
            }
        }
        return iso
    }
}
