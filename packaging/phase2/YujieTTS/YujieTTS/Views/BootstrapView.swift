import SwiftUI

/// First-launch setup wizard. Shows download/extraction progress.
struct BootstrapView: View {
    @EnvironmentObject var envManager: EnvironmentManager

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                // Icon
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.cyan.gradient)

                Text("黑鲸自定义克隆TTS")
                    .font(.largeTitle.bold())
                Text("AI语音合成引擎")
                    .font(.title3)
                    .foregroundStyle(.secondary)

                Divider()
                    .frame(maxWidth: 300)

                // Phase indicator
                phaseContent
                    .frame(maxWidth: 460)
            }

            Spacer()

            Text("黑鲸自定义克隆TTS · Powered by Qwen3-TTS + MLX · Apple Silicon")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 16)
        }
        .frame(minWidth: 560, minHeight: 440)
        .padding()
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch envManager.phase {
        case .checking:
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                Text("检查运行环境…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

        case .downloadingEnv, .downloadingModel:
            VStack(spacing: 16) {
                stepIndicator

                ProgressView(value: envManager.progress) {
                    Text(envManager.statusText)
                        .font(.callout)
                } currentValueLabel: {
                    Text("\(Int(envManager.progress * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .progressViewStyle(.linear)

                if envManager.phase == .downloadingModel {
                    Text("首次下载语音模型约 2.9GB，请耐心等待")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

        case .extractingEnv, .fixingEnv:
            VStack(spacing: 12) {
                stepIndicator
                ProgressView()
                    .controlSize(.large)
                Text(envManager.statusText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

        case .ready:
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)
                Text("环境就绪，正在启动…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

        case .failed:
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.red)
                Text("环境配置失败")
                    .font(.headline)
                if let err = envManager.errorMessage {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                Button("重试") {
                    Task { await envManager.bootstrap() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var stepIndicator: some View {
        HStack(spacing: 24) {
            stepDot("环境", done: envManager.phase != .downloadingEnv && envManager.phase != .extractingEnv && envManager.phase != .fixingEnv && envManager.phase != .checking, active: envManager.phase == .downloadingEnv || envManager.phase == .extractingEnv || envManager.phase == .fixingEnv)
            Image(systemName: "arrow.right")
                .foregroundStyle(.tertiary)
            stepDot("模型", done: envManager.phase == .ready, active: envManager.phase == .downloadingModel)
            Image(systemName: "arrow.right")
                .foregroundStyle(.tertiary)
            stepDot("就绪", done: envManager.phase == .ready, active: false)
        }
        .font(.callout)
    }

    private func stepDot(_ label: String, done: Bool, active: Bool) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(done ? Color.green : active ? Color.blue : Color.gray.opacity(0.3))
                    .frame(width: 28, height: 28)
                if done {
                    Image(systemName: "checkmark")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                } else if active {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(.white)
                }
            }
            Text(label)
                .font(.caption)
                .foregroundStyle(active ? .primary : .secondary)
        }
    }
}
