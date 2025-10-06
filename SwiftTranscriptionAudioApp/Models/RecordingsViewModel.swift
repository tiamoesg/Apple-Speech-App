import Foundation
import SwiftUI

@MainActor
final class RecordingsViewModel: ObservableObject {
    @Published private(set) var audioEntries: [AudioEntry] = []
    @Published var activeSheet: AudioEntry?

    private let persistence: AudioEntryPersistence
    private var playbackRecorder: Recorder?
    private var playbackTranscriber: SpokenWordTranscriber?
    private(set) var currentlyPlayingAudioEntryID: UUID?

    init(persistence: AudioEntryPersistence = AudioEntryPersistence()) {
        self.persistence = persistence
        loadPersistedAudioEntries()
    }

    func loadPersistedAudioEntries() {
        audioEntries = persistence.load().sorted(by: { $0.createdAt > $1.createdAt })
    }

    func createAudioEntry() -> AudioEntry {
        let audioEntry = AudioEntry.blankAudioEntry()
        audioEntry.createdAt = Date()
        audioEntries.insert(audioEntry, at: 0)
        persistence.save(audioEntries)
        activeSheet = audioEntry
        return audioEntry
    }

    func binding(for audioEntry: AudioEntry) -> Binding<AudioEntry>? {
        guard let index = audioEntries.firstIndex(where: { $0.id == audioEntry.id }) else { return nil }
        return Binding(get: { self.audioEntries[index] }, set: { newValue in
            self.audioEntries[index] = newValue
            self.persistence.save(self.audioEntries)
        })
    }

    func persist(_ audioEntry: AudioEntry) {
        guard let index = audioEntries.firstIndex(where: { $0.id == audioEntry.id }) else { return }

        objectWillChange.send()

        if audioEntry.url != nil {
            persistence.persistAudio(for: audioEntry)
            audioEntry.isOffloaded = false
        }

        audioEntries[index] = audioEntry
        audioEntries.sort(by: { $0.createdAt > $1.createdAt })
        persistence.save(audioEntries)
    }

    func delete(_ audioEntry: AudioEntry) {
        guard let index = audioEntries.firstIndex(where: { $0.id == audioEntry.id }) else { return }

        stopPlayback()
        persistence.deleteAudio(for: audioEntry)
        audioEntries.remove(at: index)
        if activeSheet?.id == audioEntry.id {
            activeSheet = nil
        }
        persistence.save(audioEntries)
    }

    func offload(_ audioEntry: AudioEntry) {
        guard let index = audioEntries.firstIndex(where: { $0.id == audioEntry.id }) else { return }

        stopPlayback()
        persistence.deleteAudio(for: audioEntry)
        objectWillChange.send()
        audioEntries[index].url = nil
        audioEntries[index].isOffloaded = true
        persistence.save(audioEntries)
    }

    func togglePlayback(for audioEntry: AudioEntry) {
        if currentlyPlayingAudioEntryID == audioEntry.id {
            stopPlayback()
        } else {
            startPlayback(for: audioEntry)
        }
    }

    private func startPlayback(for audioEntry: AudioEntry) {
        guard let url = audioEntry.url, FileManager.default.fileExists(atPath: url.path) else { return }

        stopPlayback()

        guard let binding = binding(for: audioEntry) else { return }
        let transcriber = SpokenWordTranscriber(audioEntry: binding)
        let recorder = Recorder(transcriber: transcriber, audioEntry: binding)
        recorder.prepareForPlayback(with: url)
        recorder.playRecording()

        objectWillChange.send()
        audioEntry.isPlaying = true
        playbackRecorder = recorder
        playbackTranscriber = transcriber
        currentlyPlayingAudioEntryID = audioEntry.id
    }

    func stopPlayback() {
        playbackRecorder?.stopPlaying()
        playbackRecorder = nil
        playbackTranscriber = nil

        if let id = currentlyPlayingAudioEntryID,
           let index = audioEntries.firstIndex(where: { $0.id == id }) {
            objectWillChange.send()
            audioEntries[index].isPlaying = false
        }

        currentlyPlayingAudioEntryID = nil
    }
}
