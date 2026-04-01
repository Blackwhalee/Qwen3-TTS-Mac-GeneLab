import AVFoundation
import AppKit
import Foundation
import SwiftUI
import os

/// Manages audio playback and generation history（含音色快照 + 磁盘持久化）.
@MainActor
final class AudioService: ObservableObject {
    @Published var isPlaying = false
    @Published var progress: Double = 0
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var history: [GenerationResult] = []

    var hasAudio: Bool { player != nil }

    var currentTimeFormatted: String { formatTime(currentTime) }
    var durationFormatted: String { formatTime(duration) }

    private var player: AVAudioPlayer?
    private var progressTimer: Timer?
    private var currentResult: GenerationResult?
    private let logger = Logger(subsystem: "com.yujie.tts", category: "AudioService")
    private let historyStore = GenerationHistoryStore()

    init() {
        history = historyStore.loadResults()
    }

    func load(result: GenerationResult) {
        stop()
        do {
            player = try AVAudioPlayer(data: result.audioData)
            player?.prepareToPlay()
            duration = player?.duration ?? 0
            currentTime = 0
            progress = 0
            currentResult = result

            if let idx = history.firstIndex(where: { $0.id == result.id }) {
                history.move(fromOffsets: IndexSet(integer: idx), toOffset: 0)
            } else {
                history.insert(result, at: 0)
                if history.count > 100 {
                    history = Array(history.prefix(100))
                }
            }
            persistHistory()
        } catch {
            logger.error("Failed to load audio: \(error.localizedDescription)")
        }
    }

    func play() {
        guard let player else { return }
        player.play()
        isPlaying = true
        startProgressTimer()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        stopProgressTimer()
    }

    func stop() {
        player?.stop()
        player?.currentTime = 0
        isPlaying = false
        currentTime = 0
        progress = 0
        stopProgressTimer()
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func clearHistory() {
        history.removeAll()
        persistHistory()
    }

    func deleteHistory(at offsets: IndexSet) {
        history.remove(atOffsets: offsets)
        persistHistory()
    }

    func deleteHistoryItem(id: UUID) {
        history.removeAll { $0.id == id }
        if currentResult?.id == id {
            stop()
            player = nil
            currentResult = nil
            duration = 0
        }
        persistHistory()
    }

    func exportWAV() {
        guard let data = currentResult?.audioData else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.wav]
        panel.nameFieldStringValue = "yujie_tts_output.wav"
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try data.write(to: url)
                logger.info("Exported to \(url.path)")
            } catch {
                logger.error("Export failed: \(error.localizedDescription)")
            }
        }
    }

    /// 从历史多选导出 WAV：单条用「存储为…」，多条选文件夹批量写入。
    func exportHistoryItems(_ items: [GenerationResult]) {
        guard !items.isEmpty else { return }

        if items.count == 1, let item = items.first {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.wav]
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            panel.nameFieldStringValue = "yujie_tts_\(formatter.string(from: item.timestamp)).wav"
            panel.canCreateDirectories = true
            if panel.runModal() == .OK, let url = panel.url {
                do {
                    try item.audioData.write(to: url)
                    logger.info("Exported history item to \(url.path)")
                } catch {
                    logger.error("Export failed: \(error.localizedDescription)")
                }
            }
            return
        }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "导出"
        panel.message = "请选择文件夹，将写入 \(items.count) 个 WAV 文件"
        if panel.runModal() == .OK, let dir = panel.url {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            for (idx, item) in items.enumerated() {
                let stamp = formatter.string(from: item.timestamp)
                let short = String(item.id.uuidString.prefix(8))
                let name = String(format: "yujie_tts_%02d_%@_%@.wav", idx + 1, stamp, short)
                let url = dir.appendingPathComponent(name)
                do {
                    try item.audioData.write(to: url)
                } catch {
                    logger.error("Export failed for \(name): \(error.localizedDescription)")
                }
            }
            logger.info("Exported \(items.count) files to \(dir.path)")
        }
    }

    // MARK: - Private

    private func persistHistory() {
        historyStore.save(history: history)
    }

    private func startProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let player = self.player else { return }
                self.currentTime = player.currentTime
                self.duration = player.duration
                self.progress = player.duration > 0 ? player.currentTime / player.duration : 0

                if !player.isPlaying && self.isPlaying {
                    self.isPlaying = false
                    self.stopProgressTimer()
                }
            }
        }
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    private func formatTime(_ t: TimeInterval) -> String {
        let m = Int(t) / 60
        let s = Int(t) % 60
        return String(format: "%d:%02d", m, s)
    }
}
