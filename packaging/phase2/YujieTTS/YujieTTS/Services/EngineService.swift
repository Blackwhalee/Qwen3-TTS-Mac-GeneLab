import Foundation
import SwiftUI
import os

/// Manages the Python engine sidecar and provides HTTP API to it.
@MainActor
final class EngineService: ObservableObject {
    @Published var isConnected = false
    @Published var statusMessage = ""
    /// 从历史应用音色后递增，供 `VoiceConfigPanel` 把本地 `@State` 与引擎同步
    @Published private(set) var configSyncTrigger = UUID()

    var currentVoiceDescription: String = VoiceConfig.defaultYujie.voiceDescription
    /// 合并进 VoiceDesign instruct 的表演/情感补充（与 Python voice_prompt 一致）
    var currentEmotionInstruction: String = ""
    /// CustomVoice：语气/情感 instruct（对应引擎 `emotion`）
    var currentEmotion: String = ""
    var currentSpeed: Double = 0.85
    var currentLanguage: String = "Chinese"
    var currentTaskType: String = "VOICE_DESIGN"
    var currentSpeaker: String = "serena"

    /// VOICE_CLONE：参考 WAV 整文件（上传为 base64）
    @Published var cloneReferenceWavData: Data?
    /// VOICE_CLONE：与参考音频一致的转写
    @Published var cloneReferenceText: String = ""

    /// 仅当使用 PyTorch MPS 回退时，`generate_voice_design` 等会用到以下采样参数
    var useAdvancedSampling: Bool = false
    var samplingTemperature: Double = 0.9
    var samplingTopP: Double = 1.0
    var samplingTopK: Int = 50
    var samplingRepetitionPenalty: Double = 1.05
    var samplingDoSample: Bool = true
    var samplingMaxNewTokens: Int = 2048

    private let processManager = ProcessManager()
    private var port: Int = 0
    private var healthTimer: Timer?
    private let logger = Logger(subsystem: "com.yujie.tts", category: "EngineService")

    private var baseURL: String { "http://127.0.0.1:\(port)" }

    // MARK: - Lifecycle

    func startEngine() {
        let pm = processManager
        Task.detached {
            do {
                var port: Int = 0

                // Check if engine is already running (from previous launch or dev mode)
                if let existingPort = EngineService.devModePort() {
                    if await EngineService.isPortAlive(existingPort) {
                        port = existingPort
                    } else {
                        try? FileManager.default.removeItem(atPath: ProcessManager.portFilePath())
                    }
                }

                if port == 0 {
                    port = try pm.launch()
                }

                await MainActor.run { [weak self] in
                    self?.port = port
                    self?.startHealthCheck()
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.statusMessage = "引擎启动失败: \(error.localizedDescription)"
                    self?.logger.error("Launch failed: \(error.localizedDescription)")
                }
            }
        }
    }

    nonisolated private static func isPortAlive(_ port: Int) async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(port)/health") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    func stopEngine() {
        healthTimer?.invalidate()
        healthTimer = nil
        processManager.terminate()
        isConnected = false
    }

    // MARK: - Request body

    private func generationJSONBody(text: String, format: String) throws -> Data {
        var body: [String: Any] = [
            "text": text,
            "voice_description": currentVoiceDescription,
            "emotion_instruction": currentEmotionInstruction,
            "emotion": currentEmotion,
            "language": currentLanguage,
            "speed": currentSpeed,
            "speaker": currentSpeaker,
            "task_type": currentTaskType,
            "format": format,
        ]
        if useAdvancedSampling {
            body["temperature"] = samplingTemperature
            body["top_p"] = samplingTopP
            body["top_k"] = samplingTopK
            body["repetition_penalty"] = samplingRepetitionPenalty
            body["do_sample"] = samplingDoSample
            body["max_new_tokens"] = samplingMaxNewTokens
        }
        if currentTaskType == "VOICE_CLONE" {
            body["reference_text"] = cloneReferenceText
            if let wav = cloneReferenceWavData {
                body["reference_audio_wav_base64"] = wav.base64EncodedString()
            }
        }
        return try JSONSerialization.data(withJSONObject: body)
    }

    // MARK: - Voice snapshot（历史 / 还原配置）

    func makeVoiceSnapshot() -> VoiceProfileSnapshot {
        let cloneTextOpt: String? = currentTaskType == "VOICE_CLONE"
            ? (cloneReferenceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : cloneReferenceText)
            : nil
        let cloneAudioOpt: Bool? = currentTaskType == "VOICE_CLONE"
            ? (cloneReferenceWavData != nil)
            : nil
        return VoiceProfileSnapshot(
            voiceDescription: currentVoiceDescription,
            emotionInstruction: currentEmotionInstruction,
            emotion: currentEmotion,
            speed: currentSpeed,
            language: currentLanguage,
            taskType: currentTaskType,
            speaker: currentSpeaker,
            useAdvancedSampling: useAdvancedSampling,
            samplingTemperature: samplingTemperature,
            samplingTopP: samplingTopP,
            samplingTopK: samplingTopK,
            samplingRepetitionPenalty: samplingRepetitionPenalty,
            samplingDoSample: samplingDoSample,
            samplingMaxNewTokens: samplingMaxNewTokens,
            cloneReferenceText: cloneTextOpt,
            cloneReferenceAudioPresent: cloneAudioOpt
        )
    }

    func applyVoiceSnapshot(_ snapshot: VoiceProfileSnapshot) {
        currentVoiceDescription = snapshot.voiceDescription
        currentEmotionInstruction = snapshot.emotionInstruction
        currentEmotion = snapshot.emotion
        currentSpeed = snapshot.speed
        currentLanguage = snapshot.language
        currentTaskType = snapshot.taskType
        currentSpeaker = snapshot.speaker
        useAdvancedSampling = snapshot.useAdvancedSampling
        samplingTemperature = snapshot.samplingTemperature
        samplingTopP = snapshot.samplingTopP
        samplingTopK = snapshot.samplingTopK
        samplingRepetitionPenalty = snapshot.samplingRepetitionPenalty
        samplingDoSample = snapshot.samplingDoSample
        samplingMaxNewTokens = snapshot.samplingMaxNewTokens
        if snapshot.taskType == "VOICE_CLONE" {
            cloneReferenceText = snapshot.cloneReferenceText ?? ""
            cloneReferenceWavData = nil
        } else {
            cloneReferenceText = ""
            cloneReferenceWavData = nil
        }
        configSyncTrigger = UUID()
    }

    // MARK: - Generation

    func generate(text: String) async throws -> GenerationResult {
        guard isConnected else { throw EngineError.notConnected }

        let snapshot = makeVoiceSnapshot()
        let url = URL(string: "\(baseURL)/generate")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 600

        request.httpBody = try generationJSONBody(text: text, format: "wav")

        let t0 = Date()
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw EngineError.badResponse
        }
        guard httpResponse.statusCode == 200 else {
            let detail = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw EngineError.serverError(httpResponse.statusCode, detail)
        }

        let genTime = Date().timeIntervalSince(t0)
        let duration = Double(httpResponse.value(forHTTPHeaderField: "X-Duration") ?? "0") ?? 0
        let engine = httpResponse.value(forHTTPHeaderField: "X-Engine") ?? "unknown"

        return GenerationResult(
            text: text,
            audioData: data,
            duration: duration,
            generationTime: genTime,
            engine: engine,
            timestamp: Date(),
            voiceSnapshot: snapshot
        )
    }

    // MARK: - Generation with Progress (SSE)

    struct GenerationProgress {
        var percent: Double = 0
        var elapsed: TimeInterval = 0
        var etaSeconds: TimeInterval = 0
    }

    func generateWithProgress(
        text: String,
        onProgress: @escaping (GenerationProgress) -> Void
    ) async throws -> GenerationResult {
        guard isConnected else { throw EngineError.notConnected }

        let snapshot = makeVoiceSnapshot()
        let url = URL(string: "\(baseURL)/generate/with-progress")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 600

        request.httpBody = try generationJSONBody(text: text, format: "base64")

        let t0 = Date()
        let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw EngineError.badResponse
        }

        var audioBase64: String?
        var duration: Double = 0
        var engine: String = "unknown"
        var genTime: Double = 0

        for try await line in asyncBytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))
            if payload == "[DONE]" { break }

            guard let data = payload.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = obj["type"] as? String else { continue }

            if type == "progress" {
                let p = GenerationProgress(
                    percent: obj["percent"] as? Double ?? 0,
                    elapsed: obj["elapsed"] as? Double ?? 0,
                    etaSeconds: obj["eta_seconds"] as? Double ?? 0
                )
                await MainActor.run { onProgress(p) }
            } else if type == "complete" {
                audioBase64 = obj["audio_base64"] as? String
                duration = obj["duration"] as? Double ?? 0
                genTime = obj["generation_time"] as? Double ?? 0
                engine = obj["engine"] as? String ?? "unknown"
                await MainActor.run {
                    onProgress(GenerationProgress(percent: 100, elapsed: genTime, etaSeconds: 0))
                }
            } else if type == "error" {
                let msg = obj["message"] as? String ?? "Unknown error"
                throw EngineError.serverError(500, msg)
            }
        }

        guard let b64 = audioBase64, let audioData = Data(base64Encoded: b64) else {
            throw EngineError.badResponse
        }

        return GenerationResult(
            text: text,
            audioData: audioData,
            duration: duration,
            generationTime: genTime.isZero ? Date().timeIntervalSince(t0) : genTime,
            engine: engine,
            timestamp: Date(),
            voiceSnapshot: snapshot
        )
    }

    // MARK: - Health Check

    private func startHealthCheck() {
        healthTimer?.invalidate()
        healthTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { [weak self] in
                await self?.checkHealth()
            }
        }
        Task { await checkHealth() }
    }

    private func checkHealth() async {
        guard port > 0 else { return }
        do {
            let url = URL(string: "\(baseURL)/health")!
            var request = URLRequest(url: url)
            request.timeoutInterval = 5
            let (_, response) = try await URLSession.shared.data(for: request)
            let ok = (response as? HTTPURLResponse)?.statusCode == 200
            await MainActor.run {
                self.isConnected = ok
            }
        } catch {
            await MainActor.run {
                self.isConnected = false
            }
        }
    }

    // MARK: - Dev mode

    /// In development, if engine_server.py is already running, read its port.
    nonisolated private static func devModePort() -> Int? {
        let portFile = ProcessManager.portFilePath()
        guard FileManager.default.fileExists(atPath: portFile),
              let content = try? String(contentsOfFile: portFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
              let port = Int(content), port > 0 else {
            return nil
        }
        return port
    }

    enum EngineError: LocalizedError {
        case notConnected
        case badResponse
        case serverError(Int, String)

        var errorDescription: String? {
            switch self {
            case .notConnected: return "Engine not connected"
            case .badResponse: return "Invalid response from engine"
            case .serverError(let code, let detail): return "Server error \(code): \(detail)"
            }
        }
    }
}
