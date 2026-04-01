import Foundation
import os

/// Manages the lifecycle of the Python engine server process.
/// Uses the self-contained Python environment from EnvironmentManager.
final class ProcessManager {
    private var process: Process?
    private var stdoutPipe: Pipe?
    private let logger = Logger(subsystem: "com.blackwhale.YujieTTS", category: "ProcessManager")

    var isRunning: Bool { process?.isRunning ?? false }

    /// Launch engine_server.py using the local Python and return the port.
    func launch() throws -> Int {
        let pythonPath = EnvironmentManager.pythonBin.path
        let scriptPath = EnvironmentManager.engineScript.path
        let projectSrc = EnvironmentManager.projectSrcDir.path

        let actualPython: String
        let actualScript: String

        #if DEBUG
        if FileManager.default.fileExists(atPath: pythonPath) {
            actualPython = pythonPath
            actualScript = scriptPath
        } else {
            let condaPy = "/opt/homebrew/Caskroom/miniforge/base/envs/qwen3-tts-mac-genelab/bin/python3"
            let devScript = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Qwen3-TTS-Mac-GeneLab/packaging/phase2/scripts/engine_server.py").path
            guard FileManager.default.fileExists(atPath: condaPy) else {
                throw ProcessError.pythonNotFound
            }
            actualPython = condaPy
            actualScript = devScript
        }
        #else
        actualPython = pythonPath
        actualScript = scriptPath
        #endif

        guard FileManager.default.fileExists(atPath: actualScript) else {
            throw ProcessError.scriptNotFound(actualScript)
        }
        guard FileManager.default.fileExists(atPath: actualPython) else {
            throw ProcessError.pythonNotFound
        }

        try FileManager.default.createDirectory(
            at: EnvironmentManager.appSupportDir,
            withIntermediateDirectories: true
        )

        let portFilePath = Self.portFilePath()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: actualPython)
        proc.arguments = [actualScript, "--port", "0"]

        let voiceCfg = EnvironmentManager.appSupportDir.appendingPathComponent("voice-config", isDirectory: true)
        let childEnv = EnvironmentManager.pythonProcessEnvironment(extra: [
            "YUJIE_TTS_PORT_FILE": portFilePath,
            "YUJIE_VOICE_CONFIG_DIR": voiceCfg.path,
            "PYTORCH_ENABLE_MPS_FALLBACK": "1",
            "PYTORCH_MPS_HIGH_WATERMARK_RATIO": "0.0",
            "TOKENIZERS_PARALLELISM": "false",
        ])
        proc.environment = ProcessInfo.processInfo.environment.merging(childEnv) { _, new in new }

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        stdoutPipe = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if let line = String(data: data, encoding: .utf8), !line.isEmpty {
                self?.logger.info("engine: \(line.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
        }

        proc.terminationHandler = { [weak self] proc in
            self?.logger.info("Engine exited (code \(proc.terminationStatus))")
        }

        try proc.run()
        process = proc
        logger.info("Launched engine PID \(proc.processIdentifier) using \(actualPython)")

        let port = try waitForPort(timeout: 60)
        logger.info("Engine ready on port \(port)")
        return port
    }

    func terminate() {
        guard let proc = process, proc.isRunning else { return }
        proc.terminate()
        proc.waitUntilExit()
        process = nil
        cleanPortFile()
        logger.info("Engine stopped.")
    }

    // MARK: - Private

    private func waitForPort(timeout: TimeInterval) throws -> Int {
        let portFile = Self.portFilePath()
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if FileManager.default.fileExists(atPath: portFile),
               let content = try? String(contentsOfFile: portFile, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines),
               let port = Int(content), port > 0 {
                return port
            }
            Thread.sleep(forTimeInterval: 0.3)
        }

        throw ProcessError.portTimeout
    }

    private func cleanPortFile() {
        try? FileManager.default.removeItem(atPath: Self.portFilePath())
    }

    static func portFilePath() -> String {
        EnvironmentManager.enginePortFileURL.path
    }

    enum ProcessError: LocalizedError {
        case pythonNotFound
        case scriptNotFound(String)
        case portTimeout

        var errorDescription: String? {
            switch self {
            case .pythonNotFound: return "Python 环境未安装，请重新启动 app"
            case .scriptNotFound(let p): return "引擎脚本未找到: \(p)"
            case .portTimeout: return "引擎启动超时"
            }
        }
    }
}
