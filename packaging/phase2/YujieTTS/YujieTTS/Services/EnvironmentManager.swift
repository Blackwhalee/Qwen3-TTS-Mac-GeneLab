import Foundation
import os

/// Manages the self-contained Python environment and ML models.
/// On first launch: downloads conda-pack tarball → extracts → downloads model.
/// Subsequent launches: just verifies paths exist.
@MainActor
final class EnvironmentManager: ObservableObject {

    // MARK: - Published state for UI

    @Published var phase: SetupPhase = .checking
    @Published var progress: Double = 0          // 0…1
    @Published var statusText: String = "检查环境…"
    @Published var isReady: Bool = false
    @Published var errorMessage: String?

    enum SetupPhase: Equatable {
        case checking
        case downloadingEnv
        case extractingEnv
        case downloadingModel
        case fixingEnv
        case ready
        case failed
    }

    // MARK: - Configuration

    /// Remote URLs when local tarballs are not found (GitHub Release assets).
    static let envTarballRemoteURL  = "https://github.com/Blackwhalee/-tts/releases/download/v1.0/yujie-python-env.tar.gz"
    static let srcTarballRemoteURL  = "https://github.com/Blackwhalee/-tts/releases/download/v1.0/yujie-project-src.tar.gz"
    static let modelRepoID          = "mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-8bit"

    /// Local paths to pre-built tarballs (from build_env_pack.sh).
    /// The app checks these first before attempting a remote download.
    nonisolated static var localEnvTarball: URL? {
        for candidate in localTarballSearchPaths("yujie-python-env.tar.gz") {
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }
    nonisolated static var localSrcTarball: URL? {
        for candidate in localTarballSearchPaths("yujie-project-src.tar.gz") {
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    private nonisolated static func localTarballSearchPaths(_ filename: String) -> [URL] {
        var paths: [URL] = []
        // 1. Inside app bundle Resources
        if let res = Bundle.main.resourceURL {
            paths.append(res.appendingPathComponent(filename))
        }
        // 2. Project dist/ (dev mode)
        let home = FileManager.default.homeDirectoryForCurrentUser
        paths.append(home.appendingPathComponent("Qwen3-TTS-Mac-GeneLab/dist/\(filename)"))
        // 3. Next to the .app
        if let execURL = Bundle.main.executableURL {
            let appDir = execURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            paths.append(appDir.appendingPathComponent(filename))
        }
        return paths
    }

    // MARK: - Paths (nonisolated so ProcessManager can access from any thread)

    nonisolated static var appSupportDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("YujieTTS", isDirectory: true)
    }

    /// App Sandbox 下须写入容器内；同时作为 Hugging Face 缓存根目录（勿再用 ~/.cache）
    nonisolated static var huggingFaceHome: URL {
        appSupportDir.appendingPathComponent("huggingface", isDirectory: true)
    }

    /// 与 `engine_server.py` 通过环境变量 `YUJIE_TTS_PORT_FILE` 对齐
    nonisolated static var enginePortFileURL: URL {
        appSupportDir.appendingPathComponent("engine_port.txt")
    }

    nonisolated static var pythonEnvDir: URL { appSupportDir.appendingPathComponent("python-env", isDirectory: true) }
    nonisolated static var projectSrcDir: URL { appSupportDir.appendingPathComponent("project-src", isDirectory: true) }
    nonisolated static var pythonBin: URL { pythonEnvDir.appendingPathComponent("bin/python3") }
    nonisolated static var engineScript: URL { projectSrcDir.appendingPathComponent("packaging/phase2/scripts/engine_server.py") }

    nonisolated static var modelSnapshotDir: URL {
        let slug = modelRepoID.replacingOccurrences(of: "/", with: "--")
        return huggingFaceHome.appendingPathComponent("hub/models--\(slug)/snapshots", isDirectory: true)
    }

    /// 传给 Python 子进程（App Sandbox 内 HF 缓存路径 + 依赖 PATH）
    nonisolated static func pythonProcessEnvironment(extra: [String: String] = [:]) -> [String: String] {
        var env: [String: String] = [
            "PATH": pythonEnvDir.appendingPathComponent("bin").path + ":/usr/bin:/bin",
            "PYTHONPATH": projectSrcDir.path,
            "HF_HOME": huggingFaceHome.path,
            "HUGGINGFACE_HUB_CACHE": huggingFaceHome.appendingPathComponent("hub").path,
        ]
        extra.forEach { env[$0.key] = $0.value }
        return env
    }

    private let logger = Logger(subsystem: "com.blackwhale.YujieTTS", category: "EnvManager")

    // MARK: - Public API

    /// Full bootstrap: check → download env → extract → download model → ready
    func bootstrap() async {
        phase = .checking
        statusText = "检查环境…"
        progress = 0
        errorMessage = nil

        do {
            try FileManager.default.createDirectory(at: Self.appSupportDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: Self.huggingFaceHome, withIntermediateDirectories: true)

            let envOK = FileManager.default.fileExists(atPath: Self.pythonBin.path)
            let srcOK = FileManager.default.fileExists(atPath: Self.engineScript.path)
            let modelOK = Self.isModelCached()

            if envOK && srcOK && modelOK {
                logger.info("All components ready.")
                await markReady()
                return
            }

            // --- Python Environment ---
            if !envOK {
                try await installFromTarball(
                    label: "Python 环境",
                    localFile: Self.localEnvTarball,
                    remoteURL: Self.envTarballRemoteURL,
                    destDir: Self.pythonEnvDir,
                    phaseDownload: .downloadingEnv,
                    phaseExtract: .extractingEnv
                )
                phase = .fixingEnv
                statusText = "修复 Python 环境路径…"
                try await runCondaUnpack()
            }

            // --- Project Source ---
            if !srcOK {
                try await installFromTarball(
                    label: "项目代码",
                    localFile: Self.localSrcTarball,
                    remoteURL: Self.srcTarballRemoteURL,
                    destDir: Self.projectSrcDir,
                    phaseDownload: .downloadingEnv,
                    phaseExtract: .extractingEnv
                )
            }

            // --- ML Model ---
            if !modelOK {
                phase = .downloadingModel
                statusText = "下载语音模型 (~2.9GB)…首次需要较长时间"
                progress = 0
                try await downloadModel()
            }

            await markReady()
        } catch {
            logger.error("Bootstrap failed: \(error.localizedDescription)")
            await MainActor.run {
                self.phase = .failed
                self.errorMessage = error.localizedDescription
            }
        }
    }

    /// Check if everything is in place without downloading.
    nonisolated static func isEnvironmentReady() -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: pythonBin.path)
            && fm.fileExists(atPath: engineScript.path)
            && isModelCached()
    }

    nonisolated static func isModelCached() -> Bool {
        let sd = modelSnapshotDir
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: sd.path) else { return false }
        return !items.isEmpty
    }

    // MARK: - Private: Install from tarball (local or remote)

    private func installFromTarball(
        label: String,
        localFile: URL?,
        remoteURL: String,
        destDir: URL,
        phaseDownload: SetupPhase,
        phaseExtract: SetupPhase
    ) async throws {
        let tarball: URL

        if let local = localFile {
            logger.info("Using local tarball for \(label): \(local.path)")
            phase = phaseExtract
            statusText = "正在安装\(label)（本地文件）…"
            progress = 0.5
            tarball = local
        } else {
            phase = phaseDownload
            statusText = "下载\(label)…"
            progress = 0

            guard let url = URL(string: remoteURL) else {
                throw EnvError.invalidURL(remoteURL)
            }
            let tempFile = Self.appSupportDir.appendingPathComponent(UUID().uuidString + ".tar.gz")
            let (downloaded, _) = try await downloadWithProgress(from: url, to: tempFile)
            tarball = downloaded
        }

        // Extract
        phase = phaseExtract
        statusText = "解压\(label)…"

        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        proc.arguments = ["xzf", tarball.path, "-C", destDir.path]
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            throw EnvError.extractFailed(label)
        }

        // Clean up downloaded temp file (but not local pre-built ones)
        if localFile == nil {
            try? FileManager.default.removeItem(at: tarball)
        }
        progress = 1.0
    }

    private func downloadWithProgress(from url: URL, to dest: URL) async throws -> (URL, URLResponse) {
        let (asyncBytes, response) = try await URLSession.shared.bytes(from: url)
        let totalBytes = response.expectedContentLength
        var downloadedBytes: Int64 = 0
        var data = Data()
        if totalBytes > 0 {
            data.reserveCapacity(Int(totalBytes))
        }

        for try await byte in asyncBytes {
            data.append(byte)
            downloadedBytes += 1
            if totalBytes > 0 && downloadedBytes % (1024 * 256) == 0 {
                let pct = Double(downloadedBytes) / Double(totalBytes)
                await MainActor.run {
                    self.progress = min(pct, 0.99)
                    let mb = Double(downloadedBytes) / 1_048_576
                    let totalMB = Double(totalBytes) / 1_048_576
                    self.statusText = String(format: "下载中… %.0f / %.0f MB", mb, totalMB)
                }
            }
        }

        try data.write(to: dest)
        return (dest, response)
    }

    // MARK: - Private: conda-unpack

    private func runCondaUnpack() async throws {
        let unpackScript = Self.pythonEnvDir.appendingPathComponent("bin/conda-unpack")
        guard FileManager.default.fileExists(atPath: unpackScript.path) else {
            logger.warning("conda-unpack not found, skipping (may still work)")
            return
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/bash")
        proc.arguments = [unpackScript.path]
        proc.environment = ["PATH": Self.pythonEnvDir.appendingPathComponent("bin").path + ":/usr/bin:/bin"]
        try proc.run()
        proc.waitUntilExit()
        if proc.terminationStatus != 0 {
            logger.warning("conda-unpack exited with \(proc.terminationStatus), continuing anyway")
        }
    }

    // MARK: - Private: Model download

    private func downloadModel() async throws {
        let python = Self.pythonBin.path
        guard FileManager.default.fileExists(atPath: python) else {
            throw EnvError.pythonNotFound
        }

        let downloadScript = """
        from huggingface_hub import snapshot_download
        import sys, json
        path = snapshot_download("\(Self.modelRepoID)")
        print(json.dumps({"path": path}))
        """

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: python)
        proc.arguments = ["-c", downloadScript]
        proc.environment = ProcessInfo.processInfo.environment.merging(Self.pythonProcessEnvironment()) { _, new in new }

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let line = String(data: data, encoding: .utf8), !line.isEmpty else { return }
            Task { @MainActor [weak self] in
                if line.contains("Downloading") || line.contains("Fetching") {
                    self?.statusText = "下载模型文件… \(line.trimmingCharacters(in: .whitespacesAndNewlines).suffix(60))"
                }
            }
        }

        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            throw EnvError.modelDownloadFailed
        }
        progress = 1.0
    }

    // MARK: - Private: Helpers

    private func markReady() async {
        phase = .ready
        statusText = "就绪"
        progress = 1.0
        isReady = true
    }

    enum EnvError: LocalizedError {
        case invalidURL(String)
        case extractFailed(String)
        case pythonNotFound
        case modelDownloadFailed

        var errorDescription: String? {
            switch self {
            case .invalidURL(let u): return "无效的下载地址: \(u)"
            case .extractFailed(let l): return "\(l)解压失败"
            case .pythonNotFound: return "Python 环境未就绪"
            case .modelDownloadFailed: return "模型下载失败，请检查网络"
            }
        }
    }
}
