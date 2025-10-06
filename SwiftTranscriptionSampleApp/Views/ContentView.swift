/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
The app's main view.
*/

import SwiftUI
import SwiftData
import Speech

struct ContentView: View {
    @State var selectedAudioEntry: AudioEntry?
    @State var activeAudioEntry: AudioEntry = AudioEntry.blankAudioEntry()
    
    var body: some View {
        NavigationSplitView {
            List(audioEntries, selection: $selectedAudioEntry) { audioEntry in
                NavigationLink(value: audioEntry) {
                    Text(audioEntry.title)
                }
            }

            .navigationTitle("AUDIO Sessions")

            .toolbar {
                ToolbarItem {
                    Button {
                        audioEntries.append(AudioEntry.blankAudioEntry())
                    } label: {
                        Label("New AUDIO", systemImage: "plus")
                    }
                }
            }
        } detail: {
            if selectedAudioEntry != nil {
                TranscriptView(audioEntry: $activeAudioEntry)
            } else {
                Text("Select an item")
            }
        }
        .onChange(of: selectedAudioEntry) {
            if let selectedAudioEntry {
                activeAudioEntry = selectedAudioEntry
            }
        }
    }

    @State var audioEntries: [AudioEntry] = []
}
