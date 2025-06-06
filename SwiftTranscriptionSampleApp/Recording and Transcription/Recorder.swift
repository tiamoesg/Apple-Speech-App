/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
Audio input code
*/

import Foundation
import AVFoundation
import SwiftUI

class Recorder {
    private var outputContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation? = nil
    private let audioEngine: AVAudioEngine
    private let transcriber: SpokenWordTranscriber
    var playerNode: AVAudioPlayerNode?
    
    var story: Binding<Story>
    
    var file: AVAudioFile?
    private let url: URL

    init(transcriber: SpokenWordTranscriber, story: Binding<Story>) {
        audioEngine = AVAudioEngine()
        self.transcriber = transcriber
        self.story = story
        self.url = FileManager.default.temporaryDirectory
            .appending(component: UUID().uuidString)
            .appendingPathExtension(for: .wav)
    }
    
    func record() async throws {
        self.story.url.wrappedValue = url
        guard await isAuthorized() else {
            print("user denied mic permission")
            return
        }
#if os(iOS)
        try setUpAudioSession()
#endif
        try await transcriber.setUpTranscriber()
                
        for await input in try await audioStream() {
            try await self.transcriber.streamAudioToTranscriber(input)
        }
    }
    
    func stopRecording() async throws {
        audioEngine.stop()
        story.isDone.wrappedValue = true

        try await transcriber.finishTranscribing()

        Task {
            self.story.title.wrappedValue = try await story.wrappedValue.suggestedTitle() ?? story.title.wrappedValue
        }

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
                                         format: audioEngine.inputNode.outputFormat(forBus: 0)) { [weak self] (buffer, time) in
            guard let self else { return }
            writeBufferToDisk(buffer: buffer)
            self.outputContinuation?.yield(buffer)
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        
        return AsyncStream(AVAudioPCMBuffer.self, bufferingPolicy: .unbounded) {
            continuation in
            outputContinuation = continuation
        }
    }
    
    private func setupAudioEngine() throws {
        let inputSettings = audioEngine.inputNode.inputFormat(forBus: 0).settings
        self.file = try AVAudioFile(forWriting: url,
                                    settings: inputSettings)
        
        audioEngine.inputNode.removeTap(onBus: 0)
    }
        
    func playRecording() {
        guard let file else {
            return
        }
        
        playerNode = AVAudioPlayerNode()
        guard let playerNode else {
            return
        }
        
        audioEngine.attach(playerNode)
        audioEngine.connect(playerNode,
                            to: audioEngine.outputNode,
                            format: file.processingFormat)
        
        playerNode.scheduleFile(file,
                                at: nil,
                                completionCallbackType: .dataPlayedBack) { _ in
        }
        
        do {
            try audioEngine.start()
            playerNode.play()
        } catch {
            print("error")
        }
    }
    
    func stopPlaying() {
        audioEngine.stop()
    }
}
