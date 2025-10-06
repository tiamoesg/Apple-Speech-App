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
    @Binding var recording: Recording
    @State private var isRecording = false
    @State private var isPlaying = false

    @State private var recorder: Recorder
    @State private var speechTranscriber: SpokenWordTranscriber

    @State private var downloadProgress = 0.0
    @State private var currentPlaybackTime = 0.0
    @State private var timer: Timer?

    @ObservedObject var storyModel: StoryModel
    @Environment(\.dismiss) private var dismiss

    init(recording: Binding<Recording>, storyModel: StoryModel) {
        self._recording = recording
        self.storyModel = storyModel
        let transcriber = SpokenWordTranscriber(recording: recording,
                                                knowledgeBaseService: storyModel.knowledgeBaseService)
        transcriber.onMetadataChange = { [weak storyModel] updatedRecording in
            guard let storyModel else { return }
            storyModel.persist(updatedRecording)
        }
        let destination = storyModel.destinationURL(for: recording.wrappedValue)
        let recorder = Recorder(transcriber: transcriber,
                                recording: recording,
                                destinationURL: destination) { url, duration in
            storyModel.finalizeRecording(recording.wrappedValue, from: url, duration: duration)
        }
        _recorder = State(initialValue: recorder)
        _speechTranscriber = State(initialValue: transcriber)
    }

    var body: some View {
        VStack(alignment: .leading) {
            Group {
                if !recording.isComplete {
                    liveRecordingView
                } else {
                    playbackView
                }
            }
            Spacer()
        }
        .padding(20)
        .navigationTitle(recording.title)
        .toolbar {
            ToolbarItem {
                Button { handleRecordingButtonTap() } label: {
                    if isRecording {
                        Label("Stop", systemImage: "pause.fill").tint(.red)
                    } else {
                        Label("Record", systemImage: "record.circle").tint(.red)
                    }
                }
                .disabled(recording.isComplete)
            }

            ToolbarItem {
                Button { handlePlayButtonTap() } label: {
                    let isCurrentlyPlaying = recording.isOffloaded ? recording.isPlaying : isPlaying
                    Label("Play", systemImage: isCurrentlyPlaying ? "pause.fill" : "play")
                        .foregroundStyle(.blue)
                        .font(.title)
                }
                .disabled(!recording.isComplete || !recording.isPlayable || recording.isOffloading)
            }

            ToolbarItem {
                ProgressView(value: downloadProgress, total: 100)
            }

            ToolbarItem(placement: .cancellationAction) {
                Button("Done") {
                    storyModel.activeRecording = nil
                    dismiss()
                }
            }
        }
        .onChange(of: isRecording) { oldValue, newValue in
            guard newValue != oldValue else { return }
            if newValue {
                Task {
                    do {
                        try await recorder.record()
                    } catch {
                        print("could not record: \(error)")
                    }
                }
            } else {
                Task {
                    do {
                        try await recorder.stopRecording()
                        await MainActor.run {
                            storyModel.persist(recording)
                        }
                    } catch {
                        print("could not stop recording: \(error)")
                    }
                }
            }
        }
        .onChange(of: isPlaying) { _ in
            guard !recording.isOffloaded else { return }
            handlePlayback()
        }
        .onChange(of: recording.isPlaying) { _, newValue in
            guard recording.isOffloaded else { return }
            isPlaying = newValue
        }
        .onChange(of: recording.title) { _, _ in
            storyModel.persist(recording)
        }
        .onDisappear {
            storyModel.persist(recording)
        }
    }

    @ViewBuilder
    private var liveRecordingView: some View {
        Text(speechTranscriber.finalizedTranscript + speechTranscriber.volatileTranscript)
            .font(.title)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var playbackView: some View {
        textScrollView(attributedString: recording.transcriptSplitBySentences())
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
