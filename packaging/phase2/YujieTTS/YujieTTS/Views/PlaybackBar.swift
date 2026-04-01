import SwiftUI

struct PlaybackBar: View {
    @EnvironmentObject var audio: AudioService
    /// 历史页使用列表内「导出」多选，不再在播放栏显示分享式导出按钮
    var hideExportButton: Bool = false

    var body: some View {
        HStack(spacing: 16) {
            Button {
                audio.togglePlayPause()
            } label: {
                Image(systemName: audio.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.borderless)
            .disabled(!audio.hasAudio)

            Button {
                audio.stop()
            } label: {
                Image(systemName: "stop.fill")
                    .font(.title3)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.borderless)
            .disabled(!audio.hasAudio)

            VStack(spacing: 2) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.quaternary)
                            .frame(height: 6)

                        Capsule()
                            .fill(.blue)
                            .frame(width: geo.size.width * audio.progress, height: 6)
                    }
                }
                .frame(height: 6)

                HStack {
                    Text(audio.currentTimeFormatted)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(audio.durationFormatted)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if !hideExportButton {
                Button {
                    audio.exportWAV()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.title3)
                }
                .buttonStyle(.borderless)
                .disabled(!audio.hasAudio)
                .help("导出 WAV 文件")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }
}
