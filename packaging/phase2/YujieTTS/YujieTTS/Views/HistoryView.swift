import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var audio: AudioService
    @EnvironmentObject var engine: EngineService

    @State private var isExportPickingMode = false
    @State private var exportSelectedIDs: Set<UUID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("生成历史")
                        .font(.headline)
                    Text("保存每次合成的文本、音频与完整音色参数；可一键还原到右侧配置或正文。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if !audio.history.isEmpty {
                    HStack(spacing: 8) {
                        if isExportPickingMode {
                            Button("导出") {
                                isExportPickingMode = false
                                exportSelectedIDs.removeAll()
                            }
                            .buttonStyle(.borderless)
                            .font(.caption)
                            .help("结束选择，不导出文件")

                            Button("确定") {
                                let items = audio.history.filter { exportSelectedIDs.contains($0.id) }
                                audio.exportHistoryItems(items)
                                isExportPickingMode = false
                                exportSelectedIDs.removeAll()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(exportSelectedIDs.isEmpty)
                            .help("导出所选 WAV")
                        } else {
                            Button("导出") {
                                isExportPickingMode = true
                                exportSelectedIDs.removeAll()
                            }
                            .buttonStyle(.borderless)
                            .font(.caption)
                            .help("选择记录后批量导出")
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)

            if isExportPickingMode {
                Text("请选择要导出的记录，点击圆圈切换选中，然后点「确定」。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }

            if audio.history.isEmpty {
                emptyState
            } else {
                List {
                    if isExportPickingMode {
                        ForEach(audio.history) { item in
                            HistoryRow(
                                item: item,
                                exportMode: true,
                                isExportSelected: exportSelectedIDs.contains(item.id),
                                toggleExportSelection: {
                                    if exportSelectedIDs.contains(item.id) {
                                        exportSelectedIDs.remove(item.id)
                                    } else {
                                        exportSelectedIDs.insert(item.id)
                                    }
                                },
                                play: {
                                    audio.load(result: item)
                                    audio.play()
                                },
                                applyVoice: {
                                    engine.applyVoiceSnapshot(item.voiceSnapshot)
                                },
                                restoreText: {
                                    NotificationCenter.default.post(
                                        name: .yujieRestoreTextFromHistory,
                                        object: nil,
                                        userInfo: ["text": item.text]
                                    )
                                },
                                delete: {
                                    audio.deleteHistoryItem(id: item.id)
                                }
                            )
                        }
                    } else {
                        ForEach(audio.history) { item in
                            HistoryRow(
                                item: item,
                                exportMode: false,
                                isExportSelected: false,
                                toggleExportSelection: {},
                                play: {
                                    audio.load(result: item)
                                    audio.play()
                                },
                                applyVoice: {
                                    engine.applyVoiceSnapshot(item.voiceSnapshot)
                                },
                                restoreText: {
                                    NotificationCenter.default.post(
                                        name: .yujieRestoreTextFromHistory,
                                        object: nil,
                                        userInfo: ["text": item.text]
                                    )
                                },
                                delete: {
                                    audio.deleteHistoryItem(id: item.id)
                                }
                            )
                        }
                        .onDelete(perform: audio.deleteHistory)
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "waveform.slash")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("暂无生成记录")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("成功合成后自动出现在此，并写入本机应用支持目录。")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

struct HistoryRow: View {
    let item: GenerationResult
    var exportMode: Bool = false
    var isExportSelected: Bool = false
    var toggleExportSelection: () -> Void = {}
    var play: () -> Void
    var applyVoice: () -> Void
    var restoreText: () -> Void
    var delete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if exportMode {
                Button(action: toggleExportSelection) {
                    Image(systemName: isExportSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(isExportSelected ? .primary : .secondary)
                }
                .buttonStyle(.plain)
                .help(isExportSelected ? "取消选中" : "选中以导出")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(item.text.prefix(120) + (item.text.count > 120 ? "…" : ""))
                    .font(.callout)
                    .lineLimit(3)

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: taskIcon(item.voiceSnapshot.taskType))
                        .foregroundStyle(.cyan)
                        .frame(width: 20)
                    Text(item.voiceSnapshot.summaryLine())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 10) {
                    Label(item.formattedDuration, systemImage: "clock")
                    Label(item.engine, systemImage: "cpu")
                    Spacer()
                    Text(item.formattedTimestamp)
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)

                HStack(spacing: 8) {
                    Button {
                        play()
                    } label: {
                        Label("播放", systemImage: "play.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        applyVoice()
                    } label: {
                        Label("应用音色", systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        restoreText()
                    } label: {
                        Label("填入文本", systemImage: "text.quote")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Spacer()

                    Button(role: .destructive) {
                        delete()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("删除本条")
                }
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            if exportMode {
                toggleExportSelection()
            }
        }
    }

    private func taskIcon(_ task: String) -> String {
        switch task {
        case "VOICE_CLONE": return "person.crop.circle.badge.plus"
        case "CUSTOM_VOICE": return "person.wave.2"
        default: return "theatermasks"
        }
    }
}
