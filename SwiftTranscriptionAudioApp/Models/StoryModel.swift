import AVFoundation
import Foundation
import SwiftUI

@MainActor
final class StoryModel: ObservableObject {
    @Published private(set) var recordings: [Recording] = []
    @Published var activeRecording: Recording?

    private let store: RecordingStore
    private let megaService: MegaStorageService?
    let knowledgeBaseService: KnowledgeBaseService?
    private(set) var authenticatedUserID: String?
    private var offloadTasks: [UUID: Task<Void, Never>] = [:]
    private var playbackRecorder: Recorder?
    private var playbackTranscriber: SpokenWordTranscriber?
    private var remotePlayer: AVPlayer?
    private var remotePlaybackObserver: Any?
    private var remotePlaybackTask: Task<Void, Never>?
    private(set) var currentlyPlayingRecordingID: UUID?

    init(store: RecordingStore = RecordingStore(),
         megaService: MegaStorageService? = MegaStorageService.makeDefault(),
         knowledgeBaseService: KnowledgeBaseService? = KnowledgeBaseService.makeDefault()) {
        self.store = store
        self.megaService = megaService
        self.knowledgeBaseService = knowledgeBaseService
        self.authenticatedUserID = nil
        loadPersistedRecordings()
    }

    init(session: AuthSession,
         store: RecordingStore = RecordingStore()) {
        self.store = store
        if let baseURL = session.knowledgeBaseBaseURL {
            let configuration = KnowledgeBaseService.Configuration(baseURL: baseURL,
                                                                   apiKey: session.knowledgeBaseAPIKey,
                                                                   userID: session.knowledgeBaseUserID)
            self.knowledgeBaseService = KnowledgeBaseService(configuration: configuration)
        } else {
            self.knowledgeBaseService = nil
        }

        if let email = session.megaEmail,
           let password = session.megaPassword,
           let configuration = MegaStorageService.Configuration(bundle: .main,
                                                                email: email,
                                                                password: password) {
            self.megaService = MegaStorageService(configuration: configuration)
        } else {
            self.megaService = nil
        }
        self.authenticatedUserID = session.knowledgeBaseUserID
        loadPersistedRecordings()
    }

    deinit {
        offloadTasks.values.forEach { $0.cancel() }
        remotePlaybackTask?.cancel()
    }

    var canOffloadRemotely: Bool {
        megaService != nil
    }

    func loadPersistedRecordings() {
        recordings = store.load()
    }

    func createRecording() -> Recording {
        let recording = Recording.blank()
        recordings.insert(recording, at: 0)
        store.save(recordings)
        activeRecording = recording
        return recording
    }

    func binding(for recording: Recording) -> Binding<Recording>? {
        guard let index = recordings.firstIndex(where: { $0.id == recording.id }) else { return nil }
        return Binding(get: { self.recordings[index] }, set: { newValue in
            self.recordings[index] = newValue
            self.recordings[index].updatedAt = Date()
            self.store.save(self.recordings)
        })
    }

    func finalizeRecording(_ recording: Recording, from url: URL, duration: TimeInterval) {
        guard let index = recordings.firstIndex(where: { $0.id == recording.id }) else { return }
        recordings[index].fileURL = url
        recordings[index].isOffloaded = false
        recordings[index].megaNodeHandle = nil
        recordings[index].isOffloading = false
        recordings[index].isComplete = true
        recordings[index].duration = duration
        recordings[index].fileSize = fileSize(for: url)
        recordings[index].updatedAt = Date()
        recordings.sort(by: { $0.createdAt > $1.createdAt })
        store.save(recordings)
    }

    func persist(_ recording: Recording) {
        guard let index = recordings.firstIndex(where: { $0.id == recording.id }) else { return }
        recordings[index] = recording
        recordings[index].updatedAt = Date()
        store.save(recordings)
    }

    func destinationURL(for recording: Recording) -> URL {
        store.destinationURL(for: recording.id)
    }

    func delete(_ recording: Recording) {
        guard let index = recordings.firstIndex(where: { $0.id == recording.id }) else { return }

        offloadTasks[recording.id]?.cancel()
        offloadTasks[recording.id] = nil

        stopPlayback()

        if recordings[index].fileURL != nil {
            store.deleteAudio(for: recordings[index])
            if !recordings[index].isOffloaded {
                recordings.remove(at: index)
            } else {
                recordings[index].fileURL = nil
            }
        } else if !recordings[index].isOffloaded {
            recordings.remove(at: index)
        }

        if activeRecording?.id == recording.id {
            activeRecording = nil
        }

        store.save(recordings)
    }

    func offload(_ recording: Recording) {
        guard let megaService else {
            print("MegaStorageService is not configured.")
            return
        }

        guard let index = recordings.firstIndex(where: { $0.id == recording.id }) else { return }
        guard let fileURL = recordings[index].fileURL else { return }
        guard !recordings[index].isOffloading else { return }

        stopPlayback()

        objectWillChange.send()
        recordings[index].isOffloading = true
        offloadTasks[recording.id]?.cancel()
        offloadTasks[recording.id] = Task { [weak self] @MainActor in
            guard let self else { return }
            defer { self.offloadTasks[recording.id] = nil }

            do {
                let result = try await megaService.uploadAudio(from: fileURL)
                guard !Task.isCancelled else { return }
                guard let currentIndex = self.recordings.firstIndex(where: { $0.id == recording.id }) else { return }
                let currentRecording = self.recordings[currentIndex]
                self.objectWillChange.send()
                self.store.deleteAudio(for: currentRecording)
                currentRecording.fileURL = nil
                currentRecording.isOffloaded = true
                currentRecording.megaNodeHandle = result.handle
                currentRecording.isOffloading = false
                currentRecording.updatedAt = Date()
                self.store.save(self.recordings)
            } catch {
                if let currentIndex = self.recordings.firstIndex(where: { $0.id == recording.id }) {
                    self.objectWillChange.send()
                    self.recordings[currentIndex].isOffloading = false
                }

                if !Task.isCancelled {
                    print("Failed to offload recording: \(error)")
                }
            }
        }
    }

    func togglePlayback(for recording: Recording) {
        guard !recording.isOffloading else { return }
        if currentlyPlayingRecordingID == recording.id {
            stopPlayback()
        } else {
            startPlayback(for: recording)
        }
    }

    private func startPlayback(for recording: Recording) {
        stopPlayback()

        if recording.canStreamRemotely {
            startRemotePlayback(for: recording)
            return
        }

        guard let url = recording.fileURL, FileManager.default.fileExists(atPath: url.path) else { return }

        guard let binding = binding(for: recording) else { return }
        let transcriber = SpokenWordTranscriber(recording: binding,
                                                knowledgeBaseService: knowledgeBaseService,
                                                shouldSyncWithKnowledgeBase: false)
        let destination = recording.fileURL ?? destinationURL(for: recording)
        let recorder = Recorder(transcriber: transcriber,
                                recording: binding,
                                destinationURL: destination) { _, _ in }
        recorder.prepareForPlayback(with: url)
        recorder.playRecording()

        objectWillChange.send()
        recording.isPlaying = true
        playbackRecorder = recorder
        playbackTranscriber = transcriber
        currentlyPlayingRecordingID = recording.id
    }

    func stopPlayback() {
        remotePlaybackTask?.cancel()
        remotePlaybackTask = nil
        if let observer = remotePlaybackObserver {
            NotificationCenter.default.removeObserver(observer)
            remotePlaybackObserver = nil
        }
        remotePlayer?.pause()
        remotePlayer = nil

        playbackRecorder?.stopPlaying()
        playbackRecorder = nil
        playbackTranscriber = nil

        if let id = currentlyPlayingRecordingID,
           let index = recordings.firstIndex(where: { $0.id == id }) {
            objectWillChange.send()
            recordings[index].isPlaying = false
        }

        currentlyPlayingRecordingID = nil
    }

    private func startRemotePlayback(for recording: Recording) {
        guard let megaService,
              let handle = recording.megaNodeHandle else { return }

        remotePlaybackTask?.cancel()
        remotePlaybackTask = Task { [weak self] @MainActor in
            guard let self else { return }
            defer { self.remotePlaybackTask = nil }

            do {
                let url = try await megaService.streamingURL(for: handle)
                self.beginRemotePlayback(with: url, for: recording)
            } catch {
                if !Task.isCancelled {
                    print("Failed to start remote playback: \(error)")
                }
            }
        }
    }

    @MainActor
    private func beginRemotePlayback(with url: URL, for recording: Recording) {
        let playerItem = AVPlayerItem(url: url)
        remotePlayer = AVPlayer(playerItem: playerItem)
        remotePlaybackObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                                                                        object: playerItem,
                                                                        queue: .main) { [weak self] _ in
            self?.stopPlayback()
        }
        remotePlayer?.play()

        if let index = recordings.firstIndex(where: { $0.id == recording.id }) {
            objectWillChange.send()
            recordings[index].isPlaying = true
        }

        currentlyPlayingRecordingID = recording.id
    }

    private func fileSize(for url: URL) -> Int64 {
        do {
            let resources = try url.resourceValues(forKeys: [.fileSizeKey])
            if let size = resources.fileSize {
                return Int64(size)
            }
        } catch {
            print("Failed to determine file size: \(error)")
        }
        return 0
    }

    func reset() {
        offloadTasks.values.forEach { $0.cancel() }
        offloadTasks.removeAll()
        stopPlayback()
        recordings = []
        activeRecording = nil
        authenticatedUserID = nil
        store.reset()
    }
}
