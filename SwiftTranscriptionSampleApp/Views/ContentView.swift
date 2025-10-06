/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
The app's main view.
*/

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = RecordingsViewModel()

    var body: some View {
        NavigationStack {
            RecordingListView(viewModel: viewModel)
                .navigationTitle("Recordings")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            _ = viewModel.createStory()
                        } label: {
                            Label("New Recording", systemImage: "plus")
                        }
                    }
                }
        }
        .environmentObject(viewModel)
        .sheet(item: $viewModel.activeSheet) { story in
            if let binding = viewModel.binding(for: story) {
                NavigationStack {
                    TranscriptView(story: binding)
                }
                .environmentObject(viewModel)
            } else {
                Text("Recording unavailable")
                    .padding()
            }
        }
    }
}
