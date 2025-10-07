/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
Audio input code
*/

import Foundation
import AVFoundation
import SwiftUI

class Recorder {
    private var outputContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
    private let audioEngine: AVAudioEngine
    private let transcriber: SpokenWordTranscriber
    private let finalizeRecording: @MainActor (_ url: URL, _ duration: TimeInterval) -> Void
    private let destinationURL: URL

    var playerNode: AVAudioPlayerNode?
    var recording: Binding<Recording>
    var file: AVAudioFile?

    init(transcriber: SpokenWordTranscriber,
         recording: Binding<Recording>,
         destinationURL: URL,
         finalizeRecording: @escaping @MainActor (_ url: URL, _ duration: TimeInterval) -> Void) {
        audioEngine = AVAudioEngine()
        self.transcriber = transcriber
        self.recording = recording
        self.destinationURL = destinationURL
        self.finalizeRecording = finalizeRecording
    }

    func record() async throws {
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try? FileManager.default.removeItem(at: destinationURL)
        }

        recording.fileURL.wrappedValue = destinationURL
        recording.isOffloaded.wrappedValue = false

        guard await isAuthorized() else {
            print("user denied mic permission")
            return
        }
#if os(iOS)
        try setUpAudioSession()
#endif
        try await transcriber.setUpTranscriber()

        for await input in try await audioStream() {
            try await transcriber.streamAudioToTranscriber(input)
        }
    }

    func stopRecording() async throws {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        file = nil
        recording.isComplete.wrappedValue = true

        try await transcriber.finishTranscribing()

        Task {
            self.recording.title.wrappedValue = try await recording.wrappedValue.suggestedTitle() ?? recording.title.wrappedValue
        }

        let audioFile = try AVAudioFile(forReading: destinationURL)
        let duration = Double(audioFile.length) / audioFile.processingFormat.sampleRate

        await finalizeRecording(destinationURL, duration)
    }

    func pauseRecording() {
        audioEngine.pause()
    }

    func resumeRecording() throws {
        try audioEngine.start()
    }
#if os(iOS)
    func setUpAudioSession() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .spokenAudio)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
    }
#endif

    private func audioStream() async throws -> AsyncStream<AVAudioPCMBuffer> {
        try setupAudioEngine()
        audioEngine.inputNode.installTap(onBus: 0,
                                         bufferSize: 4096,
                                         format: audioEngine.inputNode.outputFormat(forBus: 0)) { [weak self] buffer, _ in
            guard let self else { return }
            writeBufferToDisk(buffer: buffer)
            self.outputContinuation?.yield(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        return AsyncStream(AVAudioPCMBuffer.self, bufferingPolicy: .unbounded) { continuation in
            outputContinuation = continuation
        }
    }

    private func setupAudioEngine() throws {
        let inputSettings = audioEngine.inputNode.inputFormat(forBus: 0).settings
        self.file = try AVAudioFile(forWriting: destinationURL,
                                    settings: inputSettings)

        audioEngine.inputNode.removeTap(onBus: 0)
    }

    func prepareForPlayback(with url: URL) {
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            print("Failed to prepare audio file: \(error)")
        }
    }

    func playRecording() {
        if file == nil, let url = recording.fileURL.wrappedValue {
            prepareForPlayback(with: url)
        }

        guard let file else { return }

        playerNode = AVAudioPlayerNode()
        guard let playerNode else { return }

        audioEngine.attach(playerNode)
        audioEngine.connect(playerNode,
                            to: audioEngine.outputNode,
                            format: file.processingFormat)

        playerNode.scheduleFile(file,
                                at: nil,
                                completionCallbackType: .dataPlayedBack) { _ in }

        do {
            try audioEngine.start()
            playerNode.play()
        } catch {
            print("error")
        }
    }

    func stopPlaying() {
        playerNode?.stop()
        audioEngine.stop()
        playerNode = nil
    }
}
