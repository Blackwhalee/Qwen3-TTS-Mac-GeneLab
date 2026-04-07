import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var engine: EngineService
    @EnvironmentObject var purchases: PurchaseManager
    @AppStorage("outputDirectory") private var outputDir = ""
    @AppStorage("autoPlay") private var autoPlay = true
    @AppStorage("preferredEngine") private var preferredEngine = "auto"

    var body: some View {
        TabView {
            generalSettings
                .tabItem { Label("通用", systemImage: "gear") }

            modelSettings
                .tabItem { Label("模型", systemImage: "cpu") }
        }
        .frame(width: 500, height: 400)
        .padding()
        .onAppear { purchases.activateStoreKitIfNeeded() }
    }

    private var generalSettings: some View {
        Form {
            Section("播放") {
                Toggle("生成后自动播放", isOn: $autoPlay)
            }

            Section("输出") {
                HStack {
                    TextField("输出目录", text: $outputDir)
                    Button("选择…") {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = false
                        panel.canChooseDirectories = true
                        panel.allowsMultipleSelection = false
                        if panel.runModal() == .OK, let url = panel.url {
                            outputDir = url.path
                        }
                    }
                }
            }

            Section("引擎") {
                Picker("推理引擎", selection: $preferredEngine) {
                    Text("自动 (MLX 优先)").tag("auto")
                    Text("仅 MLX").tag("mlx")
                    Text("仅 PyTorch MPS").tag("pytorch_mps")
                }
            }

            Section("内购") {
                Text(purchases.statusLine())
                    .font(.callout)
                Button("恢复购买（永久权益）") {
                    Task { await purchases.restorePurchases() }
                }
                .disabled(purchases.isPurchasing)
                Text("消耗型次数无法跨设备恢复；永久权益绑定 Apple ID，换机请使用恢复购买。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let err = purchases.purchaseError, !err.isEmpty {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var modelSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("模型管理")
                .font(.headline)

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    modelRow(
                        name: "VoiceDesign (MLX 8-bit)",
                        id: "mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-8bit",
                        size: "~2.9 GB",
                        required: true
                    )
                    Divider()
                    modelRow(
                        name: "CustomVoice (MLX 8-bit)",
                        id: "mlx-community/Qwen3-TTS-12Hz-1.7B-CustomVoice-8bit",
                        size: "~2.9 GB",
                        required: false
                    )
                    Divider()
                    modelRow(
                        name: "Base（应用内「克隆」走 PyTorch：Qwen/Qwen3-TTS-12Hz-1.7B-Base）",
                        id: "Qwen/Qwen3-TTS-12Hz-1.7B-Base",
                        size: "约 4GB+",
                        required: false
                    )
                    Divider()
                    modelRow(
                        name: "Base（MLX 8-bit，可选）",
                        id: "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-8bit",
                        size: "~2.9 GB",
                        required: false
                    )
                }
                .padding(.vertical, 4)
            }

            HStack {
                Text("模型缓存: 应用支持目录内 huggingface（适配沙盒）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("打开文件夹") {
                    NSWorkspace.shared.open(EnvironmentManager.huggingFaceHome)
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }

            Spacer()
        }
        .padding()
    }

    private func modelRow(name: String, id: String, size: String, required: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(name)
                        .font(.callout.bold())
                    if required {
                        Text("必需")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(.blue.opacity(0.15), in: Capsule())
                    }
                }
                Text(size)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
    }
}
