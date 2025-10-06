import SwiftUI

struct RecordingListView: View {
    @ObservedObject var viewModel: RecordingsViewModel

    var body: some View {
        List {
            if viewModel.stories.isEmpty {
                ContentUnavailableView("No Recordings",
                                        systemImage: "waveform",
                                        description: Text("Start a new session to capture audio and transcripts."))
            }

            ForEach(viewModel.stories) { story in
                RecordingRow(story: story) {
                    viewModel.togglePlayback(for: story)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    viewModel.activeSheet = story
                }
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        viewModel.delete(story)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button {
                        viewModel.offload(story)
                    } label: {
                        Label("Offload", systemImage: "externaldrive.badge.minus")
                    }
                    .tint(.indigo)
                    .disabled(story.url == nil)
                }
            }
        }
        .listStyle(.plain)
    }
}
