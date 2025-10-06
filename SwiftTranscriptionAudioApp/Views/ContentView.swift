/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
The app's main view.
*/

import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: StoryModel
    @EnvironmentObject private var authViewModel: AuthenticationViewModel

    var body: some View {
        NavigationStack {
            RecordingListView(viewModel: viewModel)
                .navigationTitle("Recordings")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Log Out", role: .destructive, action: logout)
                    }

                    if let userID = viewModel.authenticatedUserID {
                        ToolbarItem(placement: .secondaryAction) {
                            Text("Signed in as \(userID)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            let recording = viewModel.createRecording()
                            viewModel.activeRecording = recording
                        } label: {
                            Label("New Recording", systemImage: "plus")
                        }
                    }
                }
        }
        .sheet(item: $viewModel.activeRecording) { recording in
            if let binding = viewModel.binding(for: recording) {
                TranscriptView(recording: binding, storyModel: viewModel)
            } else {
                Text("Unable to load recording")
                    .padding()
            }
        }
    }

    private func logout() {
        authViewModel.logout(currentStoryModel: viewModel)
    }
}
