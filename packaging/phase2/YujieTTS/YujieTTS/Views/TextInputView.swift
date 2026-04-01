import SwiftUI
import UniformTypeIdentifiers

struct TextInputView: View {
    @EnvironmentObject var engine: EngineService
    @EnvironmentObject var audio: AudioService
    @EnvironmentObject var purchases: PurchaseManager
    @State private var inputText = ""
    @State private var isGenerating = false
    @State private var statusMessage = ""
    @State private var showPaywall = false
    @State private var showFileImporter = false
    @State private var progressPercent: Double = 0
    @State private var progressETA: TimeInterval = 0
    @State private var progressElapsed: TimeInterval = 0

    /// 引擎与输入是否允许点击「生成」（内购不足时仍可点，会弹出购买）
    private var engineReadyForGeneration: Bool {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isGenerating, engine.isConnected else { return false }
        if engine.currentTaskType == "VOICE_CLONE" {
            if engine.cloneReferenceWavData == nil { return false }
            let refTxt = engine.cloneReferenceText.trimmingCharacters(in: .whitespacesAndNewlines)
            if refTxt.isEmpty { return false }
        }
        return true
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("文本输入")
                    .font(.headline)
                Spacer()
                Text("\(inputText.count) 字")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    showFileImporter = true
                } label: {
                    Label("导入文件", systemImage: "doc")
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal)

            TextEditor(text: $inputText)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                )
                .frame(minHeight: 200)
                .padding(.horizontal)
                .onDrop(of: [.plainText, .fileURL], isTargeted: nil) { providers in
                    handleDrop(providers)
                }

            // Progress bar area
            if isGenerating {
                VStack(spacing: 6) {
                    ProgressView(value: progressPercent, total: 100) {
                        EmptyView()
                    }
                    .progressViewStyle(.linear)
                    .tint(.cyan)

                    HStack {
                        Text(String(format: "%.0f%%", progressPercent))
                            .font(.caption.bold().monospacedDigit())
                            .foregroundStyle(.cyan)

                        Spacer()

                        if progressElapsed > 0 {
                            Text(String(format: "已用 %ds", Int(progressElapsed)))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }

                        if progressETA > 1 {
                            Text("·")
                                .foregroundStyle(.tertiary)
                            Text(String(format: "预计剩余 %ds", Int(progressETA)))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }

                        if progressPercent >= 95 && progressETA <= 1 {
                            Text("即将完成…")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    if engine.currentTaskType == "VOICE_CLONE" {
                        Text("克隆模式为整段推理")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(purchases.statusLine())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                if !statusMessage.isEmpty && !isGenerating {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button {
                    Task { await generate() }
                } label: {
                    HStack(spacing: 6) {
                        if isGenerating {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "play.fill")
                        }
                        Text(isGenerating ? "生成中…" : "生成语音")
                    }
                    .frame(minWidth: 100)
                }
                .buttonStyle(.borderedProminent)
                .tint(isGenerating ? .gray : .cyan)
                .disabled(!engineReadyForGeneration)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .padding(.top, 8)
        .animation(.easeInOut(duration: 0.3), value: isGenerating)
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .environmentObject(purchases)
        }
        .onReceive(NotificationCenter.default.publisher(for: .yujieRestoreTextFromHistory)) { note in
            if let text = note.userInfo?["text"] as? String {
                inputText = text
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.plainText],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                if let content = try? String(contentsOf: url, encoding: .utf8) {
                    inputText = content
                }
            }
        }
    }

    private func generate() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        guard purchases.canStartGeneration else {
            showPaywall = true
            return
        }

        isGenerating = true
        progressPercent = 0
        progressETA = 0
        progressElapsed = 0
        statusMessage = ""

        do {
            let result = try await engine.generateWithProgress(text: text) { progress in
                self.progressPercent = progress.percent
                self.progressElapsed = progress.elapsed
                self.progressETA = progress.etaSeconds
            }
            audio.load(result: result)
            audio.play()
            purchases.recordSuccessfulGeneration()
            statusMessage = String(
                format: "完成 (%.1fs音频, 用时%.1fs)",
                result.duration,
                result.generationTime
            )
        } catch {
            statusMessage = "失败: \(error.localizedDescription)"
        }

        isGenerating = false
        progressPercent = 0
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { data, _ in
                    if let data = data as? Data, let text = String(data: data, encoding: .utf8) {
                        DispatchQueue.main.async { inputText = text }
                    }
                }
                return true
            }
        }
        return false
    }
}
