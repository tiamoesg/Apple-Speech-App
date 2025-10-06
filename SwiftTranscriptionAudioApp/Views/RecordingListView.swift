import SwiftUI

struct RecordingListView: View {
    @ObservedObject var viewModel: StoryModel

    var body: some View {
        List {
            if viewModel.recordings.isEmpty {
                ContentUnavailableView("No Recordings",
                                        systemImage: "waveform",
                                        description: Text("Start a new session to capture audio and transcripts."))
            }

            ForEach(viewModel.recordings) { recording in
                RecordingRow(recording: recording) {
                    viewModel.togglePlayback(for: recording)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    viewModel.activeRecording = recording
                }
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        viewModel.delete(recording)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .disabled(recording.isOffloaded)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button {
                        viewModel.offload(recording)
                    } label: {
                        Label("Offload", systemImage: "externaldrive.badge.minus")
                    }
                    .tint(.indigo)
                    .disabled(recording.fileURL == nil)
                }
            }
        }
        .listStyle(.plain)
    }
}
