/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
Live transcription code
*/

import Foundation
import Speech
import SwiftUI

@Observable
final class SpokenWordTranscriber {
    private var inputSequence: AsyncStream<AnalyzerInput>?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var recognizerTask: Task<(), Error>?
    private let knowledgeBaseService: KnowledgeBaseService?
    private let shouldSyncWithKnowledgeBase: Bool
    var onMetadataChange: ((Recording) -> Void)?
    
    static let magenta = Color(red: 0.54, green: 0.02, blue: 0.6).opacity(0.8) // #e81cff
    
    // The format of the audio.
    var analyzerFormat: AVAudioFormat?
    
    var converter = BufferConverter()
    var downloadProgress: Progress?
    var onDownloadProgressChange: ((Progress?) -> Void)?
    private var downloadProgressObservation: NSKeyValueObservation?
    
    var recording: Binding<Recording>
    
    var volatileTranscript: AttributedString = ""
    var finalizedTranscript: AttributedString = ""
    
    static let locale = Locale(components: .init(languageCode: .english, script: nil, languageRegion: .unitedStates))
    
    init(recording: Binding<Recording>,
         knowledgeBaseService: KnowledgeBaseService? = nil,
         shouldSyncWithKnowledgeBase: Bool = true) {
        self.recording = recording
        self.knowledgeBaseService = knowledgeBaseService
        self.shouldSyncWithKnowledgeBase = shouldSyncWithKnowledgeBase
    }
    
    func setUpTranscriber() async throws {
        transcriber = SpeechTranscriber(locale: Locale.current,
                                        transcriptionOptions: [],
                                        reportingOptions: [.volatileResults],
                                        attributeOptions: [.audioTimeRange])

        guard let transcriber else {
            throw TranscriptionError.failedToSetupRecognitionStream
        }

        analyzer = SpeechAnalyzer(modules: [transcriber])
        
        do {
            try await ensureModel(transcriber: transcriber, locale: Locale.current)
        } catch let error as TranscriptionError {
            print(error)
            return
        }
        
        self.analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
        (inputSequence, inputBuilder) = AsyncStream<AnalyzerInput>.makeStream()
        
        guard let inputSequence else { return }
        
        recognizerTask = Task {
            do {
                for try await case let result in transcriber.results {
                    let text = result.text
                    if result.isFinal {
                        finalizedTranscript += text
                        volatileTranscript = ""
                        updateRecording(withFinal: text)
                    } else {
                        volatileTranscript = text
                        volatileTranscript.foregroundColor = .purple.opacity(0.4)
                    }
                }
            } catch {
                print("speech recognition failed")
            }
        }
        
        try await analyzer?.start(inputSequence: inputSequence)
    }
    
    func updateRecording(withFinal str: AttributedString) {
        recording.transcript.wrappedValue.append(str)
        guard shouldSyncWithKnowledgeBase, knowledgeBaseService != nil else { return }
        enqueueKnowledgeBaseUpload(forFinalSegment: str)
    }

    private func enqueueKnowledgeBaseUpload(forFinalSegment segment: AttributedString) {
        let segmentText = String(segment.characters)
        Task { [weak self] in
            guard let self else { return }
            await self.syncKnowledgeBase(finalSegmentText: segmentText)
        }
    }

    @MainActor
    private func syncKnowledgeBase(finalSegmentText: String) async {
        guard let knowledgeBaseService else { return }

        let trimmedSegment = finalSegmentText.trimmingCharacters(in: .whitespacesAndNewlines)
        var metadata = recording.wrappedValue.metadata.updatingKnowledgeBaseSync { sync in
            sync.status = .pending
            sync.lastAttemptedAt = Date()
            sync.lastErrorMessage = nil
        }

        recording.wrappedValue.metadata = metadata
        recording.wrappedValue.updatedAt = Date()
        onMetadataChange?(recording.wrappedValue)

        let appendedSegment = trimmedSegment.isEmpty ? nil : finalSegmentText
        let transcriptText = String(recording.wrappedValue.transcript.characters)

        let metadataPayload = KnowledgeBaseService.TranscriptSubmission.MetadataPayload(
            recordingTitle: recording.wrappedValue.title,
            recordingUpdatedAt: recording.wrappedValue.updatedAt,
            appendedSegment: appendedSegment,
            knowledgeBaseStatus: recording.wrappedValue.metadata.knowledgeBaseSync.status.rawValue,
            knowledgeBaseIdentifiers: recording.wrappedValue.metadata.knowledgeBaseSync.remoteIdentifiers,
            knowledgeBaseLastSyncedAt: recording.wrappedValue.metadata.knowledgeBaseSync.lastSyncedAt,
            knowledgeBaseLastAttemptedAt: recording.wrappedValue.metadata.knowledgeBaseSync.lastAttemptedAt,
            knowledgeBaseLastError: recording.wrappedValue.metadata.knowledgeBaseSync.lastErrorMessage,
            knowledgeBaseLastKnownRemoteStatus: recording.wrappedValue.metadata.knowledgeBaseSync.lastKnownRemoteStatus,
            appRecordingID: recording.wrappedValue.id.uuidString,
            appFileURL: recording.wrappedValue.fileURL?.path
        )

        let submission = KnowledgeBaseService.TranscriptSubmission(
            id: recording.wrappedValue.id,
            userID: nil,
            fileName: recording.wrappedValue.fileURL?.lastPathComponent ?? RecordingFileCoordinator.defaultAudioFileName(for: recording.wrappedValue.id),
            transcriptionText: transcriptText,
            speaker: nil,
            createdAt: recording.wrappedValue.createdAt,
            processed: false,
            metadata: metadataPayload,
            fileSize: recording.wrappedValue.fileSize,
            duration: recording.wrappedValue.duration,
            sourcePath: recording.wrappedValue.fileURL?.path,
            mp3Path: nil,
            confidenceScore: nil,
            languageDetected: nil,
            tags: []
        )

        do {
            let result = try await knowledgeBaseService.submitTranscript(submission)
            metadata = recording.wrappedValue.metadata.updatingKnowledgeBaseSync { sync in
                sync.status = .success
                if !result.identifiers.isEmpty {
                    sync.remoteIdentifiers = result.identifiers
                }
                sync.lastSyncedAt = Date()
                sync.lastKnownRemoteStatus = result.status ?? sync.lastKnownRemoteStatus
                sync.lastErrorMessage = nil
            }
            recording.wrappedValue.metadata = metadata
        } catch {
            metadata = recording.wrappedValue.metadata.updatingKnowledgeBaseSync { sync in
                sync.status = .error
                sync.lastErrorMessage = error.localizedDescription
            }
            recording.wrappedValue.metadata = metadata
        }

        recording.wrappedValue.updatedAt = Date()
        onMetadataChange?(recording.wrappedValue)
    }
    
    func streamAudioToTranscriber(_ buffer: AVAudioPCMBuffer) async throws {
        guard let inputBuilder, let analyzerFormat else {
            throw TranscriptionError.invalidAudioDataType
        }
        
        let converted = try self.converter.convertBuffer(buffer, to: analyzerFormat)
        let input = AnalyzerInput(buffer: converted)
        
        inputBuilder.yield(input)
    }
    
    public func finishTranscribing() async throws {
        inputBuilder?.finish()
        try await analyzer?.finalizeAndFinishThroughEndOfInput()
        recognizerTask?.cancel()
        recognizerTask = nil
    }
}

extension SpokenWordTranscriber {
    public func ensureModel(transcriber: SpeechTranscriber, locale: Locale) async throws {
        guard await supported(locale: locale) else {
            throw TranscriptionError.localeNotSupported
        }
        
        if await installed(locale: locale) {
            return
        } else {
            try await downloadIfNeeded(for: transcriber)
        }
    }
    
    func supported(locale: Locale) async -> Bool {
        let supported = await SpeechTranscriber.supportedLocales
        return supported.map { $0.identifier(.bcp47) }.contains(locale.identifier(.bcp47))
    }

    func installed(locale: Locale) async -> Bool {
        let installed = await Set(SpeechTranscriber.installedLocales)
        return installed.map { $0.identifier(.bcp47) }.contains(locale.identifier(.bcp47))
    }

    func downloadIfNeeded(for module: SpeechTranscriber) async throws {
        if let downloader = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            downloadProgress = downloader.progress
            notifyDownloadProgressChange(downloadProgress)

            downloadProgressObservation = downloader.progress.observe(\.fractionCompleted, options: [.new]) { [weak self] progress, _ in
                guard let self else { return }
                self.notifyDownloadProgressChange(progress)
            }

            defer {
                downloadProgressObservation?.invalidate()
                downloadProgressObservation = nil
                downloadProgress = nil
                notifyDownloadProgressChange(nil)
            }

            try await downloader.downloadAndInstall()
        }
    }
    
    func releaseLocales() async {
        let reserved = await AssetInventory.reservedLocales
        for locale in reserved {
            await AssetInventory.release(reservedLocale: locale)
        }
    }
}

extension SpokenWordTranscriber {
    private func notifyDownloadProgressChange(_ progress: Progress?) {
        Task { @MainActor in
            self.onDownloadProgressChange?(progress)
        }
    }
}
