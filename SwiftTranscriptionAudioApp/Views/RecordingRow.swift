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

                    knowledgeBaseStatusBadge

                    if recording.isOffloading {
                        Label("Uploading…", systemImage: "arrow.up.circle")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    } else if recording.isOffloaded {
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
            .disabled(!recording.isPlayable || recording.isOffloading)
            .accessibilityLabel(recording.isPlaying ? "Stop playback" : "Play recording")
        }
        .padding(.vertical, 8)
    }
}

private extension RecordingRow {
    @ViewBuilder
    var knowledgeBaseStatusBadge: some View {
        switch recording.knowledgeBaseSyncStatus {
        case .idle:
            EmptyView()
        case .pending:
            statusBadge(text: "Syncing", systemImage: "arrow.triangle.2.circlepath", tint: .blue)
        case .success:
            let hasRemotes = !recording.knowledgeBaseRemoteIdentifiers.isEmpty
            statusBadge(text: hasRemotes ? "Synced" : "Uploaded", systemImage: "checkmark.seal.fill", tint: .green)
                .help(hasRemotes ? "Remote IDs: \(recording.knowledgeBaseRemoteIdentifiers.joined(separator: ", "))" : "Transcript synced successfully")
        case .error:
            statusBadge(text: "Sync Failed", systemImage: "exclamationmark.triangle.fill", tint: .red)
                .help(recording.knowledgeBaseSyncErrorDescription ?? "The last knowledge base sync attempt failed.")
        }
    }

    @ViewBuilder
    func statusBadge(text: String, systemImage: String, tint: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(tint)
            .background(tint.opacity(0.12), in: Capsule())
            .labelStyle(.titleAndIcon)
    }
}
