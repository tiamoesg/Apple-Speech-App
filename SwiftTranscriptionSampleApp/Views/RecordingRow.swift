import SwiftUI
import Observation

struct RecordingRow: View {
    @Bindable var story: Story
    let togglePlayback: () -> Void

    init(story: Story, togglePlayback: @escaping () -> Void) {
        self._story = Bindable(story)
        self.togglePlayback = togglePlayback
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(story.title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                HStack(spacing: 8) {
                    Text(story.formattedTimestamp)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if story.isOffloaded {
                        Label("Offloaded", systemImage: "icloud.slash")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }

            Spacer()

            Text(story.fileSizeDescription)
                .font(.caption)
                .foregroundStyle(.secondary)

            Button(action: togglePlayback) {
                Image(systemName: story.isPlaying ? "stop.fill" : "play.fill")
                    .font(.title3)
            }
            .buttonStyle(.borderless)
            .disabled(story.url == nil)
            .accessibilityLabel(story.isPlaying ? "Stop playback" : "Play recording")
        }
        .padding(.vertical, 8)
    }
}
