import Foundation

/// 用户声库：JSON 清单 + 克隆参考音 WAV 文件
@MainActor
final class VoiceLibraryStore: ObservableObject {
    @Published private(set) var userEntries: [VoiceLibraryEntry] = []

    private let entriesURL: URL
    private let audioDir: URL
    private let fm = FileManager.default

    private static var supportRoot: URL {
        let bid = Bundle.main.bundleIdentifier ?? "com.blackwhale.YujieTTS"
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent(bid, isDirectory: true)
    }

    init() {
        let root = Self.supportRoot
        entriesURL = root.appendingPathComponent("voice_library_entries.json")
        audioDir = root.appendingPathComponent("VoiceLibraryAudio", isDirectory: true)
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        try? fm.createDirectory(at: audioDir, withIntermediateDirectories: true)
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: entriesURL),
              let decoded = try? JSONDecoder().decode([VoiceLibraryEntry].self, from: data) else {
            userEntries = []
            return
        }
        userEntries = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(userEntries) else { return }
        try? data.write(to: entriesURL, options: .atomic)
    }

    /// 将当前引擎配置写入声库（仅允许从设计 / 克隆模式添加）
    func addCurrent(from engine: EngineService, displayName rawName: String) -> String? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return "请填写声库名称。" }

        let tt = engine.currentTaskType
        if tt != "VOICE_DESIGN" && tt != "VOICE_CLONE" {
            return "请先在「设计」或「克隆」中调好参数后再添加。"
        }

        if tt == "VOICE_CLONE" {
            if engine.cloneReferenceWavData == nil {
                return "克隆条目需要已选择参考 WAV。"
            }
            let t = engine.cloneReferenceText.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty {
                return "克隆条目需要填写参考转写。"
            }
        }

        if tt == "VOICE_DESIGN" {
            let desc = engine.currentVoiceDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            if desc.isEmpty {
                return "设计条目至少需要填写音色描述。"
            }
        }

        let snap = engine.makeVoiceSnapshot()

        if tt == "VOICE_CLONE", let wav = engine.cloneReferenceWavData {
            let entryId = UUID()
            let refName = "\(entryId.uuidString).wav"
            let url = audioDir.appendingPathComponent(refName)
            do {
                try wav.write(to: url, options: .atomic)
            } catch {
                return "无法写入参考音频: \(error.localizedDescription)"
            }
            let entry = VoiceLibraryEntry(id: entryId, name: name, snapshot: snap, referenceAudioFileName: refName)
            userEntries.insert(entry, at: 0)
            persist()
            pruneOrphanAudio()
            return nil
        }

        let entry = VoiceLibraryEntry(name: name, snapshot: snap, referenceAudioFileName: nil)
        userEntries.insert(entry, at: 0)
        persist()
        pruneOrphanAudio()
        return nil
    }

    func removeEntry(id: UUID) {
        guard let idx = userEntries.firstIndex(where: { $0.id == id }) else { return }
        let removed = userEntries.remove(at: idx)
        if let fn = removed.referenceAudioFileName {
            let url = audioDir.appendingPathComponent(fn)
            try? fm.removeItem(at: url)
        }
        persist()
        pruneOrphanAudio()
    }

    func applyEntry(_ entry: VoiceLibraryEntry, engine: EngineService) {
        engine.applyVoiceSnapshot(entry.snapshot)
        if entry.snapshot.taskType == "VOICE_CLONE", let fn = entry.referenceAudioFileName {
            let url = audioDir.appendingPathComponent(fn)
            engine.cloneReferenceWavData = try? Data(contentsOf: url)
        }
    }

    private func pruneOrphanAudio() {
        let keep = Set(userEntries.compactMap(\.referenceAudioFileName))
        guard let files = try? fm.contentsOfDirectory(at: audioDir, includingPropertiesForKeys: nil) else { return }
        for f in files where f.lastPathComponent.hasSuffix(".wav") {
            if !keep.contains(f.lastPathComponent) {
                try? fm.removeItem(at: f)
            }
        }
    }
}
