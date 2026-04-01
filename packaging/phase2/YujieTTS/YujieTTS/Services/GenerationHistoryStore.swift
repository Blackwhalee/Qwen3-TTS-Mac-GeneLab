import Foundation

/// 磁盘持久化：生成历史元数据 + 每条对应 WAV 文件
private struct PersistedGenerationRecord: Codable {
    let id: UUID
    let text: String
    let voiceSnapshot: VoiceProfileSnapshot
    let duration: TimeInterval
    let generationTime: TimeInterval
    let engine: String
    let timestamp: Date
    let audioFileName: String
}

final class GenerationHistoryStore {
    private let fm = FileManager.default
    private let rootDir: URL
    private let audioDir: URL
    private let manifestURL: URL

    init() {
        let bid = Bundle.main.bundleIdentifier ?? "com.blackwhale.YujieTTS"
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        rootDir = base.appendingPathComponent(bid, isDirectory: true)
        audioDir = rootDir.appendingPathComponent("HistoryAudio", isDirectory: true)
        manifestURL = rootDir.appendingPathComponent("generation_history.json")
        try? fm.createDirectory(at: rootDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: audioDir, withIntermediateDirectories: true)
    }

    func loadResults() -> [GenerationResult] {
        guard let data = try? Data(contentsOf: manifestURL),
              let records = try? JSONDecoder().decode([PersistedGenerationRecord].self, from: data),
              !records.isEmpty else {
            return []
        }

        return records.compactMap { rec in
            let url = audioDir.appendingPathComponent(rec.audioFileName)
            guard let audioData = try? Data(contentsOf: url), !audioData.isEmpty else {
                return nil
            }
            return GenerationResult(
                id: rec.id,
                text: rec.text,
                audioData: audioData,
                duration: rec.duration,
                generationTime: rec.generationTime,
                engine: rec.engine,
                timestamp: rec.timestamp,
                voiceSnapshot: rec.voiceSnapshot
            )
        }
    }

    func save(history: [GenerationResult]) {
        let records: [PersistedGenerationRecord] = history.map { r in
            PersistedGenerationRecord(
                id: r.id,
                text: r.text,
                voiceSnapshot: r.voiceSnapshot,
                duration: r.duration,
                generationTime: r.generationTime,
                engine: r.engine,
                timestamp: r.timestamp,
                audioFileName: "\(r.id.uuidString).wav"
            )
        }

        let keepNames = Set(records.map(\.audioFileName))

        for r in history {
            let name = "\(r.id.uuidString).wav"
            let url = audioDir.appendingPathComponent(name)
            try? r.audioData.write(to: url, options: .atomic)
        }

        if let files = try? fm.contentsOfDirectory(at: audioDir, includingPropertiesForKeys: nil) {
            for f in files where f.lastPathComponent.hasSuffix(".wav") {
                if !keepNames.contains(f.lastPathComponent) {
                    try? fm.removeItem(at: f)
                }
            }
        }

        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: manifestURL, options: .atomic)
    }
}
