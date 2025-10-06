import SwiftUI

struct RecordingListView: View {
    @ObservedObject var viewModel: RecordingsViewModel

    var body: some View {
        List {
            if viewModel.audioEntries.isEmpty {
                ContentUnavailableView("No Recordings",
                                        systemImage: "waveform",
                                        description: Text("Start a new session to capture audio and transcripts."))
            }

            ForEach(viewModel.audioEntries) { audioEntry in
                AudioEntryRow(audioEntry: audioEntry) {
                    viewModel.togglePlayback(for: audioEntry)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    viewModel.activeSheet = audioEntry
                }
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        viewModel.delete(audioEntry)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button {
                        viewModel.offload(audioEntry)
                    } label: {
                        Label("Offload", systemImage: "externaldrive.badge.minus")
                    }
                    .tint(.indigo)
                    .disabled(audioEntry.url == nil)
                }
            }
        }
        .listStyle(.plain)
    }
}
