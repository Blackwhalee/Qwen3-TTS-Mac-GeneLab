import SwiftUI
import UniformTypeIdentifiers

struct VoiceConfigPanel: View {
    @EnvironmentObject var engine: EngineService
    @EnvironmentObject var voiceLibrary: VoiceLibraryStore
    @State private var voiceDescription: String = VoiceConfig.defaultYujie.voiceDescription
    @State private var emotionInstruction: String = ""
    @State private var customEmotion: String = ""
    @State private var speed: Double = 0.85
    @State private var language = "Chinese"
    @State private var taskType = "VOICE_DESIGN"
    @State private var speaker = "serena"
    @State private var advancedExpanded = false
    @State private var useAdvancedSampling = false
    @State private var samplingTemperature: Double = 0.9
    @State private var samplingTopP: Double = 1.0
    @State private var samplingTopK: Double = 50
    @State private var samplingRepetitionPenalty: Double = 1.05
    @State private var samplingDoSample = true
    @State private var samplingMaxNewTokens: Double = 2048
    @State private var showCloneImporter = false
    @State private var newLibraryEntryName: String = ""
    @State private var librarySaveError: String?
    @State private var showLibraryError = false
    @State private var voiceBankSource: VoiceBankSource = .initial

    private let languages = ["Chinese", "English", "Japanese", "Korean", "French", "German", "Spanish"]
    /// 顺序：设计 → 克隆 → 声库（与原「预设/克隆」位置互换）
    private let taskTypes: [(String, String)] = [
        ("VOICE_DESIGN", "设计"),
        ("VOICE_CLONE", "克隆"),
        ("CUSTOM_VOICE", "声库"),
    ]

    private let speakers = [
        "serena", "vivian", "aiden", "ryan", "eric",
        "dylan", "ono_anna", "sohee", "uncle_fu",
    ]

    private enum VoiceBankSource: String {
        case initial
        case mine
    }

    var body: some View {
        syncFromHistoryAndCoreFields(scrollColumn)
            .onChange(of: useAdvancedSampling) { _, newValue in engine.useAdvancedSampling = newValue }
            .onChange(of: samplingTemperature) { _, newValue in engine.samplingTemperature = newValue }
            .onChange(of: samplingTopP) { _, newValue in engine.samplingTopP = newValue }
            .onChange(of: samplingTopK) { _, newValue in engine.samplingTopK = Int(newValue.rounded()) }
            .onChange(of: samplingRepetitionPenalty) { _, newValue in engine.samplingRepetitionPenalty = newValue }
            .onChange(of: samplingDoSample) { _, newValue in engine.samplingDoSample = newValue }
            .onChange(of: samplingMaxNewTokens) { _, newValue in engine.samplingMaxNewTokens = Int(newValue.rounded()) }
            .fileImporter(
                isPresented: $showCloneImporter,
                allowedContentTypes: [.wav],
                allowsMultipleSelection: false
            ) { result in
                guard case .success(let urls) = result, let url = urls.first else { return }
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                engine.cloneReferenceWavData = try? Data(contentsOf: url)
            }
            .alert("无法保存", isPresented: $showLibraryError, actions: {
                Button("好", role: .cancel) {}
            }, message: {
                Text(librarySaveError ?? "")
            })
    }

    private func syncFromHistoryAndCoreFields<V: View>(_ view: V) -> some View {
        view
            .onAppear { syncUIFromEngine() }
            .onChange(of: engine.configSyncTrigger) { _, _ in syncUIFromEngine() }
            .onChange(of: voiceDescription) { _, newValue in engine.currentVoiceDescription = newValue }
            .onChange(of: emotionInstruction) { _, newValue in engine.currentEmotionInstruction = newValue }
            .onChange(of: customEmotion) { _, newValue in engine.currentEmotion = newValue }
            .onChange(of: speed) { _, newValue in engine.currentSpeed = newValue }
            .onChange(of: language) { _, newValue in engine.currentLanguage = newValue }
            .onChange(of: taskType) { _, newValue in
                engine.currentTaskType = newValue
                if newValue != "VOICE_CLONE" {
                    engine.cloneReferenceWavData = nil
                    engine.cloneReferenceText = ""
                }
            }
            .onChange(of: speaker) { _, newValue in engine.currentSpeaker = newValue }
    }

    private var scrollColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("音色配置")
                    .font(.headline)
                taskTypeGroup
                cloneVoiceGroups
                voiceDescriptionGroup
                emotionSupplementGroup
                addToLibrarySection
                voiceBankSection
                basicParamsGroup
                advancedDisclosure
                designTemplateGroup
                Spacer()
            }
            .padding()
        }
    }

    private var taskTypeGroup: some View {
        GroupBox("任务类型") {
            Picker("", selection: $taskType) {
                ForEach(taskTypes, id: \.0) { value, label in
                    Text(label).tag(value)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    @ViewBuilder
    private var addToLibrarySection: some View {
        if taskType == "VOICE_DESIGN" || taskType == "VOICE_CLONE" {
            GroupBox("添加到声库") {
                Text("将当前「设计」或「克隆」下的参数保存为一条带名称的声库条目；在「声库」页可一键应用。克隆条目会同时保存参考 WAV。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    TextField("声库名称", text: $newLibraryEntryName)
                        .textFieldStyle(.roundedBorder)
                    Button("添加") {
                        if let err = voiceLibrary.addCurrent(from: engine, displayName: newLibraryEntryName) {
                            librarySaveError = err
                            showLibraryError = true
                        } else {
                            newLibraryEntryName = ""
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.cyan)
                }
            }
        }
    }

    @ViewBuilder
    private var voiceBankSection: some View {
        if taskType == "CUSTOM_VOICE" {
            GroupBox("声库角色") {
                VStack(alignment: .leading, spacing: 10) {
                    Button {
                        voiceBankSource = .initial
                    } label: {
                        HStack(spacing: 10) {
                            HStack(spacing: 8) {
                                Text("初始")
                                    .font(.callout.weight(.semibold))
                                Picker("", selection: $speaker) {
                                    ForEach(speakers, id: \.self) { id in
                                        Text(speakerDisplayName(id)).tag(id)
                                    }
                                }
                                .labelsHidden()
                                .disabled(voiceBankSource != .initial)
                            }
                            Spacer()
                            selectionDot(isSelected: voiceBankSource == .initial)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)

                    Divider()

                    Button {
                        voiceBankSource = .mine
                    } label: {
                        HStack(spacing: 10) {
                            Text("我的声库")
                                .font(.callout.weight(.semibold))
                            Spacer()
                            selectionDot(isSelected: voiceBankSource == .mine)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)

                    VStack(alignment: .leading, spacing: 8) {
                        if voiceLibrary.userEntries.isEmpty {
                            Text("暂无保存条目。在「设计」或「克隆」中调好参数后，用「添加到声库」保存。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(Array(voiceLibrary.userEntries.enumerated()), id: \.element.id) { index, entry in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(entry.name)
                                            .font(.callout.weight(.semibold))
                                        Spacer()
                                        Button("应用") {
                                            voiceBankSource = .mine
                                            voiceLibrary.applyEntry(entry, engine: engine)
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                        Button(role: .destructive) {
                                            voiceLibrary.removeEntry(id: entry.id)
                                        } label: {
                                            Image(systemName: "trash")
                                        }
                                        .buttonStyle(.borderless)
                                    }
                                    Text(entry.snapshot.summaryLine())
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(2)
                                }
                                .padding(.vertical, 4)
                                if index < voiceLibrary.userEntries.count - 1 {
                                    Divider()
                                }
                            }
                        }
                    }
                    .disabled(voiceBankSource != .mine)
                    .opacity(voiceBankSource == .mine ? 1 : 0.45)
                }
            }
            GroupBox("语气 / 情感（可选）") {
                TextField("例如：用特别温柔、带点撒娇的语气", text: $customEmotion, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(2...5)
                    .font(.callout)
                Text("与「附加风格描述」二选一时，本字段优先作为 instruct。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func selectionDot(isSelected: Bool) -> some View {
        Image(systemName: isSelected ? "record.circle.fill" : "circle")
            .foregroundStyle(isSelected ? .cyan : .secondary)
            .font(.title3)
            .accessibilityLabel(isSelected ? "已选择" : "未选择")
    }

    @ViewBuilder
    private var cloneVoiceGroups: some View {
        if taskType == "VOICE_CLONE" {
            GroupBox("声音克隆") {
                Text("使用 PyTorch 与 HuggingFace 模型 Qwen/Qwen3-TTS-12Hz-1.7B-Base（首次克隆会自动下载，体积约数 GB；推理在 CPU 上运行）。参考音请用 WAV，约 3～15 秒；转写需与音频内容一致。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Button("选择参考 WAV…") {
                        showCloneImporter = true
                    }
                    if engine.cloneReferenceWavData != nil {
                        Label("已选文件", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else {
                        Text("未选择")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                TextField(
                    "参考音频对应原文（转写）",
                    text: Binding(
                        get: { engine.cloneReferenceText },
                        set: { engine.cloneReferenceText = $0 }
                    ),
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .lineLimit(3...10)
                .font(.callout)
            }
        }
    }

    @ViewBuilder
    private var voiceDescriptionGroup: some View {
        if taskType != "VOICE_CLONE" {
            GroupBox(taskType == "VOICE_DESIGN" ? "音色描述（VoiceDesign instruct）" : "附加风格描述（可选）") {
                TextEditor(text: $voiceDescription)
                    .font(.callout)
                    .frame(minHeight: taskType == "VOICE_DESIGN" ? 100 : 56)
                    .scrollContentBackground(.hidden)
                HStack {
                    Button("重置默认") {
                        voiceDescription = VoiceConfig.defaultYujie.voiceDescription
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .disabled(taskType != "VOICE_DESIGN")
                    Spacer()
                    Text("\(voiceDescription.count) 字")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    @ViewBuilder
    private var emotionSupplementGroup: some View {
        if taskType == "VOICE_DESIGN" {
            GroupBox("表演 / 情感补充") {
                TextEditor(text: $emotionInstruction)
                    .font(.callout)
                    .frame(minHeight: 72)
                    .scrollContentBackground(.hidden)
                Text("会追加到音色描述后一并作为 instruct；不影响「声库」内置角色模式。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                HStack {
                    Spacer()
                    Text("\(emotionInstruction.count) 字")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var basicParamsGroup: some View {
        GroupBox("参数") {
            VStack(spacing: 12) {
                HStack {
                    Text("语速")
                        .frame(width: 40, alignment: .leading)
                    Slider(value: $speed, in: 0.5...1.5, step: 0.05)
                    Text(String(format: "%.2f", speed))
                        .font(.caption.monospacedDigit())
                        .frame(width: 36)
                }
                HStack {
                    Text("语言")
                        .frame(width: 40, alignment: .leading)
                    Picker("", selection: $language) {
                        ForEach(languages, id: \.self) { Text($0) }
                    }
                    .labelsHidden()
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var advancedDisclosure: some View {
        DisclosureGroup(isExpanded: $advancedExpanded) {
            advancedSamplingInner
        } label: {
            Text("高级：推理采样（PyTorch）")
                .font(.subheadline.weight(.medium))
        }
    }

    private var advancedSamplingInner: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("启用自定义采样参数", isOn: $useAdvancedSampling)
            Text("仅在使用 PyTorch MPS 推理时生效（MLX 路径由 mlx-audio 内部处理，会忽略下列项）。适合调试随机性、重复抑制等。")
                .font(.caption2)
                .foregroundStyle(.secondary)
            advancedSlider("temperature", value: $samplingTemperature, range: 0.1...1.5, step: 0.05, enabled: useAdvancedSampling)
            advancedSlider("top_p", value: $samplingTopP, range: 0.5...1.0, step: 0.05, enabled: useAdvancedSampling)
            advancedSlider("top_k", value: $samplingTopK, range: 1...100, step: 1, enabled: useAdvancedSampling)
            advancedSlider("repetition_penalty", value: $samplingRepetitionPenalty, range: 1.0...1.5, step: 0.02, enabled: useAdvancedSampling)
            Toggle("do_sample", isOn: $samplingDoSample)
                .disabled(!useAdvancedSampling)
            HStack {
                Text("max_new_tokens")
                    .font(.caption)
                Spacer()
                Stepper(value: Binding(
                    get: { Int(samplingMaxNewTokens) },
                    set: { samplingMaxNewTokens = Double($0) }
                ), in: 256...4096, step: 256) {
                    Text("\(Int(samplingMaxNewTokens))")
                        .font(.caption.monospacedDigit())
                }
                .disabled(!useAdvancedSampling)
            }
            Button("恢复默认采样值") {
                samplingTemperature = 0.9
                samplingTopP = 1.0
                samplingTopK = 50
                samplingRepetitionPenalty = 1.05
                samplingDoSample = true
                samplingMaxNewTokens = 2048
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .disabled(!useAdvancedSampling)
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var designTemplateGroup: some View {
        if taskType == "VOICE_DESIGN" {
            GroupBox("设计模板") {
                VStack(spacing: 6) {
                    templateButton("御姐 (默认)", desc: VoiceConfig.defaultYujie.voiceDescription)
                    templateButton("萝莉", desc: "体现撒娇稚嫩的萝莉女声，音调偏高且起伏明显，营造出黏人、卖萌的听觉效果。")
                    templateButton("温柔姐姐", desc: "温柔知性的成熟女声，语速舒缓，声音轻柔如耳语，带有安抚感和亲和力。")
                    templateButton("冷酷女王", desc: "冷傲高贵的女王音，声音低沉有力，不带感情波动，充满压迫感和距离感。")
                }
            }
        }
    }

    private func syncUIFromEngine() {
        voiceDescription = engine.currentVoiceDescription
        emotionInstruction = engine.currentEmotionInstruction
        customEmotion = engine.currentEmotion
        speed = engine.currentSpeed
        language = engine.currentLanguage
        taskType = engine.currentTaskType
        speaker = engine.currentSpeaker
        useAdvancedSampling = engine.useAdvancedSampling
        samplingTemperature = engine.samplingTemperature
        samplingTopP = engine.samplingTopP
        samplingTopK = Double(engine.samplingTopK)
        samplingRepetitionPenalty = engine.samplingRepetitionPenalty
        samplingDoSample = engine.samplingDoSample
        samplingMaxNewTokens = Double(engine.samplingMaxNewTokens)

        // 声库页：根据是否存在「我的声库」条目决定默认选中
        if taskType == "CUSTOM_VOICE" {
            voiceBankSource = .initial
        }
    }

    @ViewBuilder
    private func advancedSlider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        enabled: Bool
    ) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .frame(width: 120, alignment: .leading)
            Slider(value: value, in: range, step: step)
                .disabled(!enabled)
            Text(String(format: "%.2f", value.wrappedValue))
                .font(.caption2.monospacedDigit())
                .frame(width: 40)
        }
    }

    private func speakerDisplayName(_ id: String) -> String {
        switch id {
        case "serena": return "Serena"
        case "vivian": return "Vivian"
        case "aiden": return "Aiden"
        case "ryan": return "Ryan"
        case "eric": return "Eric"
        case "dylan": return "Dylan"
        case "ono_anna": return "Ono Anna"
        case "sohee": return "Sohee"
        case "uncle_fu": return "Uncle Fu"
        default: return id
        }
    }

    private func templateButton(_ title: String, desc: String) -> some View {
        Button {
            voiceDescription = desc
        } label: {
            HStack {
                Text(title)
                    .font(.callout)
                Spacer()
                if voiceDescription == desc {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .padding(.vertical, 2)
    }
}
