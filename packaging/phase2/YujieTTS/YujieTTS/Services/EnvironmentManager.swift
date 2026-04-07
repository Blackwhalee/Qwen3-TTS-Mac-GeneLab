import Foundation
import os

/// Manages the self-contained Python environment and ML models.
/// **App Store：** 环境与源码包应打进 `Resources/bootstrap/`，首启从本地包解压，不经 GitHub。
/// 若包内缺失（仅开发或未跑 prepare 脚本）则回退到 `~/…/dist` 与 HTTPS。
/// 模型仍可能从 Hugging Face 拉取（体积大，需网络）。
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

    /// 仅当应用包与本地 dist 均无归档时的回退地址（开发/灾备）。
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

    private static let bundledBootstrapDir = "bootstrap"

    private nonisolated static func localTarballSearchPaths(_ filename: String) -> [URL] {
        var paths: [URL] = []
        let fm = FileManager.default

        // 1. App Store：Resources/bootstrap/（与 Apple 分发的主包一同到达用户）
        if let res = Bundle.main.resourceURL {
            let inBootstrap = res.appendingPathComponent("\(bundledBootstrapDir)/\(filename)")
            paths.append(inBootstrap)
            paths.append(res.appendingPathComponent(filename))
        }

        // 2. 开发机 GeneLab dist/
        let home = fm.homeDirectoryForCurrentUser
        paths.append(home.appendingPathComponent("Qwen3-TTS-Mac-GeneLab/dist/\(filename)"))

        // 3. 与 .app 同目录（本地测试）
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

    /// 在 `python-env` 下查找真实解释器：可能仅有 `python3.12`、`bin` 在子目录内等。
    nonisolated static func findPythonInterpreterUnderEnvRoot() -> URL? {
        let fm = FileManager.default
        let root = pythonEnvDir
        let preferredNames = ["python3", "python", "python3.13", "python3.12", "python3.11", "python3.10"]

        func pick(inBinDir bin: URL) -> URL? {
            for name in preferredNames {
                let p = bin.appendingPathComponent(name)
                if fm.isExecutableFile(atPath: p.path) { return p }
            }
            guard let files = try? fm.contentsOfDirectory(at: bin, includingPropertiesForKeys: nil) else { return nil }
            for f in files {
                let n = f.lastPathComponent
                guard n.hasPrefix("python"), !n.hasSuffix(".dylib") else { continue }
                if fm.isExecutableFile(atPath: f.path) { return f }
            }
            return nil
        }

        func tryEnvRoot(_ envRoot: URL) -> URL? {
            pick(inBinDir: envRoot.appendingPathComponent("bin"))
        }

        if let u = tryEnvRoot(root) { return u }
        guard let subs = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return nil
        }
        for sub in subs {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: sub.path, isDirectory: &isDir), isDir.boolValue else { continue }
            if let u = tryEnvRoot(sub) { return u }
            if let subs2 = try? fm.contentsOfDirectory(at: sub, includingPropertiesForKeys: nil) {
                for sub2 in subs2 {
                    var isD2: ObjCBool = false
                    guard fm.fileExists(atPath: sub2.path, isDirectory: &isD2), isD2.boolValue else { continue }
                    if let u = tryEnvRoot(sub2) { return u }
                }
            }
        }

        if let en = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
            for case let item as URL in en {
                guard item.path.contains("/bin/") else { continue }
                let n = item.lastPathComponent
                guard n.hasPrefix("python"), !n.hasSuffix(".dylib") else { continue }
                if fm.isExecutableFile(atPath: item.path) { return item }
            }
        }
        return nil
    }

    /// conda-pack 解压后的环境根目录（含 `bin/` 的那一层）。
    nonisolated static func resolvedPythonEnvironmentRoot() -> URL {
        if let interp = findPythonInterpreterUnderEnvRoot() {
            return interp.deletingLastPathComponent().deletingLastPathComponent()
        }
        return pythonEnvDir
    }

    nonisolated static var pythonBin: URL {
        if let u = findPythonInterpreterUnderEnvRoot() { return u }
        let r = resolvedPythonEnvironmentRoot()
        return r.appendingPathComponent("bin/python3")
    }
    nonisolated static var engineScript: URL { projectSrcDir.appendingPathComponent("packaging/phase2/scripts/engine_server.py") }

    nonisolated static var modelSnapshotDir: URL {
        let slug = modelRepoID.replacingOccurrences(of: "/", with: "--")
        return huggingFaceHome.appendingPathComponent("hub/models--\(slug)/snapshots", isDirectory: true)
    }

    /// 传给 Python 子进程（App Sandbox 内 HF 缓存路径 + 依赖 PATH）
    nonisolated static func pythonProcessEnvironment(extra: [String: String] = [:]) -> [String: String] {
        let binPath = findPythonInterpreterUnderEnvRoot()?.deletingLastPathComponent().path
            ?? resolvedPythonEnvironmentRoot().appendingPathComponent("bin").path
        var env: [String: String] = [
            "PATH": binPath + ":/usr/bin:/bin",
            "PYTHONPATH": projectSrcDir.path,
            "HF_HOME": huggingFaceHome.path,
            "HUGGINGFACE_HUB_CACHE": huggingFaceHome.appendingPathComponent("hub").path,
        ]
        extra.forEach { env[$0.key] = $0.value }
        return env
    }

    private let logger = Logger(subsystem: "com.blackwhale.YujieTTS", category: "EnvManager")

    /// 大文件下载：避免 `bytes` 整包读入 `Data` 导致内存暴涨与假死（环境包数百 MB）。
    private static let downloadSession: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForResource = 7200
        cfg.timeoutIntervalForRequest = 120
        return URLSession(configuration: cfg)
    }()

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

            // 解压/下载得到的 Mach-O 常带 com.apple.quarantine，会导致 isExecutableFile 失败或无法启动子进程
            if FileManager.default.fileExists(atPath: Self.pythonEnvDir.path) {
                await stripQuarantineFromTree(at: Self.pythonEnvDir)
            }
            if FileManager.default.fileExists(atPath: Self.projectSrcDir.path) {
                await stripQuarantineFromTree(at: Self.projectSrcDir)
            }

            let envOK = FileManager.default.isExecutableFile(atPath: Self.pythonBin.path)
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
        return fm.isExecutableFile(atPath: pythonBin.path)
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
            let fromBundle = local.path.hasPrefix(Bundle.main.bundlePath)
            statusText = fromBundle
                ? "正在安装\(label)（应用内资源，不经外网下载）…"
                : "正在安装\(label)（本机文件）…"
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
            let minBytes = Self.minimumBytesForRemoteTarball(urlString: remoteURL)
            let (downloaded, _) = try await downloadWithProgress(from: url, to: tempFile, minimumBytes: minBytes)
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

        await stripQuarantineFromTree(at: destDir)

        // Clean up downloaded temp file (but not local pre-built ones)
        if localFile == nil {
            try? FileManager.default.removeItem(at: tarball)
        }
        progress = 1.0
    }

    /// 移除 Gatekeeper 隔离属性，否则沙盒内可能无法执行 conda 环境中的 python 与动态库。
    private func stripQuarantineFromTree(at root: URL) async {
        guard FileManager.default.fileExists(atPath: root.path) else { return }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        proc.arguments = ["-dr", "com.apple.quarantine", root.path]
        do {
            try proc.run()
            proc.waitUntilExit()
            if proc.terminationStatus != 0 {
                logger.warning("xattr quarantine strip exited \(proc.terminationStatus) for \(root.path)")
            }
        } catch {
            logger.warning("xattr failed: \(error.localizedDescription)")
        }
    }

    /// `yujie-project-src` 仅百余 KB 合法；`python-env` 应为数百 MB 级。
    private nonisolated static func minimumBytesForRemoteTarball(urlString: String) -> Int64 {
        if urlString.contains("yujie-project-src") { return 2048 }
        if urlString.contains("yujie-python-env") { return 8 * 1024 * 1024 }
        return 512 * 1024
    }

    private func downloadWithProgress(from url: URL, to dest: URL, minimumBytes: Int64) async throws -> (URL, URLResponse) {
        await MainActor.run {
            self.progress = 0.02
            self.statusText = minimumBytes < 1024 * 1024
                ? "正在下载项目源码包…"
                : "环境包较大，正在下载到磁盘（请耐心等待，勿关闭应用）…"
        }

        let tmp: URL
        let response: URLResponse
        do {
            (tmp, response) = try await Self.downloadSession.download(from: url)
        } catch {
            let msg = (error as NSError).localizedDescription
            throw EnvError.downloadFailed("网络错误：\(msg)")
        }

        guard let http = response as? HTTPURLResponse else {
            try? FileManager.default.removeItem(at: tmp)
            throw EnvError.downloadFailed("无效的 HTTP 响应")
        }

        guard (200...299).contains(http.statusCode) else {
            let snippet = (try? String(contentsOf: tmp, encoding: .utf8))?.prefix(400) ?? ""
            try? FileManager.default.removeItem(at: tmp)
            if snippet.contains("<!DOCTYPE") || snippet.contains("<html") {
                throw EnvError.downloadFailed(
                    "HTTP \(http.statusCode)：收到网页而非安装包。请检查 Release 中是否仍有该资源，或网络是否需要代理。"
                )
            }
            throw EnvError.downloadFailed("HTTP \(http.statusCode)")
        }

        let attrs = try? FileManager.default.attributesOfItem(atPath: tmp.path)
        let sz = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        if sz < minimumBytes {
            try? FileManager.default.removeItem(at: tmp)
            throw EnvError.downloadFailed(
                String(format: "下载文件过小（%lld 字节），低于预期 %lld，链接可能失效或被墙。", sz, minimumBytes)
            )
        }

        await MainActor.run {
            self.progress = 0.95
            let mb = Double(sz) / 1_048_576
            self.statusText = String(format: "下载完成（约 %.0f MB），准备解压…", mb)
        }

        if FileManager.default.fileExists(atPath: dest.path) {
            try? FileManager.default.removeItem(at: dest)
        }
        do {
            try FileManager.default.moveItem(at: tmp, to: dest)
        } catch {
            try? FileManager.default.removeItem(at: tmp)
            throw EnvError.downloadFailed("保存文件失败：\(error.localizedDescription)")
        }

        return (dest, response)
    }

    // MARK: - Private: conda-unpack

    private func runCondaUnpack() async throws {
        let envRoot = Self.resolvedPythonEnvironmentRoot()
        let unpackScript = envRoot.appendingPathComponent("bin/conda-unpack")
        guard FileManager.default.fileExists(atPath: unpackScript.path) else {
            logger.warning("conda-unpack not found, skipping (may still work)")
            return
        }

        let python = Self.pythonBin
        guard FileManager.default.isExecutableFile(atPath: python.path) else {
            logger.warning("python interpreter not found, skipping conda-unpack")
            return
        }
        let proc = Process()
        proc.executableURL = python
        proc.arguments = [unpackScript.path]
        proc.environment = ["PATH": envRoot.appendingPathComponent("bin").path + ":/usr/bin:/bin"]
        try proc.run()
        proc.waitUntilExit()
        if proc.terminationStatus != 0 {
            logger.warning("conda-unpack exited with \(proc.terminationStatus), continuing anyway")
        }
    }

    // MARK: - Private: Model download

    private func downloadModel() async throws {
        let python = Self.pythonBin.path
        guard FileManager.default.isExecutableFile(atPath: python) else {
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
        case downloadFailed(String)
        case pythonNotFound
        case modelDownloadFailed

        var errorDescription: String? {
            switch self {
            case .invalidURL(let u): return "无效的下载地址: \(u)"
            case .extractFailed(let l): return "\(l)解压失败（若环境包损坏，请删除应用数据后重试）"
            case .downloadFailed(let m): return m
            case .pythonNotFound:
                return "未找到可用的 Python 解释器（已搜索 python-env 下各层 bin/）。请删除本应用数据后重试；若仍失败请重新打包 conda 环境。"
            case .modelDownloadFailed: return "模型下载失败：请检查能否访问 Hugging Face；国内网络可能需要代理或在审核备注中说明。"
            }
        }
    }
}
