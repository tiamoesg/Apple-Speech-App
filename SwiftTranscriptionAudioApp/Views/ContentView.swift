/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
The app's main view.
*/

import SwiftUI

struct ContentView: View {
    @StateObject private var storyModel = StoryModel()

    var body: some View {
        NavigationStack {
            RecordingListView(viewModel: storyModel)
                .navigationTitle("Recordings")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            let recording = storyModel.createRecording()
                            storyModel.activeRecording = recording
                        } label: {
                            Label("New Recording", systemImage: "plus")
                        }
                    }
                }
        }
        .sheet(item: $storyModel.activeRecording) { recording in
            if let binding = storyModel.binding(for: recording) {
                TranscriptView(recording: binding, storyModel: storyModel)
            } else {
                Text("Unable to load recording")
                    .padding()
            }
        }
    }
}
