/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
The transcript view.
*/

import Foundation
import SwiftUI
import Speech
import AVFoundation

struct TranscriptView: View {
    @Binding var audioEntry: AudioEntry
    @State var isRecording = false
    @State var isPlaying = false

    @State var recorder: Recorder
    @State var speechTranscriber: SpokenWordTranscriber
    
    @State var downloadProgress = 0.0
    
    @State var currentPlaybackTime = 0.0
    
    @State var timer: Timer?
    
    init(audioEntry: Binding<AudioEntry>) {
        self._audioEntry = audioEntry
        let transcriber = SpokenWordTranscriber(audioEntry: audioEntry)
        recorder = Recorder(transcriber: transcriber, audioEntry: audioEntry)
        speechTranscriber = transcriber
    }

    var body: some View {
        VStack(alignment: .leading) {
            Group {
                if !audioEntry.isDone {
                    liveRecordingView
                } else {
                    playbackView
                }
            }
            Spacer()
        }
        .padding(20)
        .navigationTitle(audioEntry.title)
        .toolbar {
            ToolbarItem {
                Button {
                    handleRecordingButtonTap()
                } label: {
                    if isRecording {
                        Label("Stop", systemImage: "pause.fill").tint(.red)
                    } else {
                        Label("Record", systemImage: "record.circle").tint(.red)
                    }
                }
                .disabled(audioEntry.isDone)
            }

            ToolbarItem {
                Button {
                    handlePlayButtonTap()
                } label: {
                    Label("Play", systemImage: isPlaying ? "pause.fill" : "play").foregroundStyle(.blue).font(.title)
                }
                .disabled(!audioEntry.isDone)
            }

            ToolbarItem {
                ProgressView(value: downloadProgress, total: 100)
            }
            
        }
        .onChange(of: isRecording) { oldValue, newValue in
            guard newValue != oldValue else { return }
            if newValue == true {
                Task {
                    do {
                        try await recorder.record()
                    } catch {
                        print("could not record: \(error)")
                    }
                }
            } else {
                Task {
                    try await recorder.stopRecording()
                }
            }
        }
        .onChange(of: isPlaying) {
            handlePlayback()
        }
    }

    @ViewBuilder
    var liveRecordingView: some View {
        Text(speechTranscriber.finalizedTranscript + speechTranscriber.volatileTranscript)
            .font(.title)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    @ViewBuilder
    var playbackView: some View {
        textScrollView(attributedString: audioEntry.audioTranscriptBrokenUpByLines())
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
