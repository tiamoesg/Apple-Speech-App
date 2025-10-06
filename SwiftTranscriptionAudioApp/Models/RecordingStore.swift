import Foundation

struct RecordingStore {
    private let fileCoordinator: RecordingFileCoordinator

    init(fileManager: FileManager = .default,
         fileCoordinator: RecordingFileCoordinator? = nil) {
        self.fileCoordinator = fileCoordinator ?? RecordingFileCoordinator(fileManager: fileManager)
    }

    func load() -> [Recording] {
        guard let data = try? Data(contentsOf: fileCoordinator.storeURL) else { return [] }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let recordings = try decoder.decode([Recording].self, from: data)
            return recordings.sorted(by: { $0.createdAt > $1.createdAt })
        } catch {
            print("Failed to load recordings: \(error)")
            return []
        }
    }

    func save(_ recordings: [Recording]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601

        do {
            let data = try encoder.encode(recordings)
            try data.write(to: fileCoordinator.storeURL, options: .atomic)
        } catch {
            print("Failed to persist recordings: \(error)")
        }
    }

    func deleteAudio(for recording: Recording) {
        guard let url = recording.fileURL else { return }
        fileCoordinator.deleteAudioIfNeeded(at: url)
    }

    static func recordingsDirectory(fileManager: FileManager = .default) -> URL {
        RecordingFileCoordinator(fileManager: fileManager).recordingsDirectory
    }

    static func audioURL(for id: UUID, fileManager: FileManager = .default) -> URL {
        RecordingFileCoordinator(fileManager: fileManager).audioURL(for: id)
    }

    func destinationURL(for id: UUID) -> URL {
        fileCoordinator.audioURL(for: id)
    }

    func reset() {
        fileCoordinator.reset()
    }
}
