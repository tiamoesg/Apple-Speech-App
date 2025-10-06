import SwiftUI
import Observation

struct RecordingRow: View {
    @Bindable var recording: Recording
    let togglePlayback: () -> Void

    init(recording: Recording, togglePlayback: @escaping () -> Void) {
        self._recording = Bindable(recording)
        self.togglePlayback = togglePlayback
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(recording.title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                HStack(spacing: 8) {
                    Text(recording.formattedTimestamp)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if recording.isOffloaded {
                        Label("Offloaded", systemImage: "icloud.slash")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(recording.durationDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(recording.fileSizeDescription)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Button(action: togglePlayback) {
                Image(systemName: recording.isPlaying ? "stop.fill" : "play.fill")
                    .font(.title3)
            }
            .buttonStyle(.borderless)
            .disabled(recording.fileURL == nil)
            .accessibilityLabel(recording.isPlaying ? "Stop playback" : "Play recording")
        }
        .padding(.vertical, 8)
    }
}
