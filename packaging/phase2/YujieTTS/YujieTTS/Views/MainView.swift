import SwiftUI

struct MainView: View {
    @EnvironmentObject var engine: EngineService
    @EnvironmentObject var audio: AudioService
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            headerBar

            HSplitView {
                VStack(spacing: 0) {
                    TabView(selection: $selectedTab) {
                        TextInputView()
                            .tabItem { Label("生成", systemImage: "waveform") }
                            .tag(0)

                        HistoryView()
                            .tabItem { Label("历史", systemImage: "clock") }
                            .tag(1)
                    }
                    .padding(.top, 8)
                }
                .frame(minWidth: 500)

                VoiceConfigPanel()
                    .frame(minWidth: 300, idealWidth: 360, maxWidth: 420)
            }

            PlaybackBar(hideExportButton: selectedTab == 1)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onReceive(NotificationCenter.default.publisher(for: .yujieRestoreTextFromHistory)) { _ in
            selectedTab = 0
        }
    }

    private var headerBar: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "waveform.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.cyan)
                Text("黑鲸自定义克隆TTS")
                    .font(.title2.bold())
                Text("AI语音合成")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            engineStatusBadge
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    @ViewBuilder
    private var engineStatusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(engine.isConnected ? .green : .red)
                .frame(width: 8, height: 8)
            Text(engine.isConnected ? "引擎就绪" : "连接中…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.quaternary, in: Capsule())
    }
}
