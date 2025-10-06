import SwiftUI
import Observation

struct AudioEntryRow: View {
    @Bindable var audioEntry: AudioEntry
    let togglePlayback: () -> Void

    init(audioEntry: AudioEntry, togglePlayback: @escaping () -> Void) {
        self._audioEntry = Bindable(audioEntry)
        self.togglePlayback = togglePlayback
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(audioEntry.title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                HStack(spacing: 8) {
                    Text(audioEntry.formattedTimestamp)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if audioEntry.isOffloaded {
                        Label("Offloaded", systemImage: "icloud.slash")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }

            Spacer()

            Text(audioEntry.fileSizeDescription)
                .font(.caption)
                .foregroundStyle(.secondary)

            Button(action: togglePlayback) {
                Image(systemName: audioEntry.isPlaying ? "stop.fill" : "play.fill")
                    .font(.title3)
            }
            .buttonStyle(.borderless)
            .disabled(audioEntry.url == nil)
            .accessibilityLabel(audioEntry.isPlaying ? "Stop playback" : "Play recording")
        }
        .padding(.vertical, 8)
    }
}
