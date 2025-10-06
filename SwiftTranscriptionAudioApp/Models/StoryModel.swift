import Foundation
import SwiftUI

@MainActor
final class StoryModel: ObservableObject {
    @Published private(set) var recordings: [Recording] = []
    @Published var activeRecording: Recording?

    private let store: RecordingStore
    private var playbackRecorder: Recorder?
    private var playbackTranscriber: SpokenWordTranscriber?
    private(set) var currentlyPlayingRecordingID: UUID?

    init(store: RecordingStore = RecordingStore()) {
        self.store = store
        loadPersistedRecordings()
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
        guard let index = recordings.firstIndex(where: { $0.id == recording.id }) else { return }

        stopPlayback()
        store.deleteAudio(for: recordings[index])
        recordings[index].fileURL = nil
        recordings[index].isOffloaded = true
        recordings[index].updatedAt = Date()
        store.save(recordings)
    }

    func togglePlayback(for recording: Recording) {
        if currentlyPlayingRecordingID == recording.id {
            stopPlayback()
        } else {
            startPlayback(for: recording)
        }
    }

    private func startPlayback(for recording: Recording) {
        guard let url = recording.fileURL, FileManager.default.fileExists(atPath: url.path) else { return }

        stopPlayback()

        guard let binding = binding(for: recording) else { return }
        let transcriber = SpokenWordTranscriber(recording: binding)
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
}
