import Foundation

struct RecordingStore {
    private enum Constants {
        static let storeFileName = "recordings.json"
        static let recordingsDirectoryName = "Recordings"
    }

    private let fileManager: FileManager
    private let storeURL: URL

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let baseDirectory = RecordingStore.baseDirectory(fileManager: fileManager)
        self.storeURL = baseDirectory.appendingPathComponent(Constants.storeFileName)

        let recordingsDirectory = RecordingStore.recordingsDirectory(fileManager: fileManager)
        if !fileManager.fileExists(atPath: recordingsDirectory.path) {
            try? fileManager.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)
        }
    }

    func load() -> [Recording] {
        guard let data = try? Data(contentsOf: storeURL) else { return [] }

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
            try data.write(to: storeURL, options: .atomic)
        } catch {
            print("Failed to persist recordings: \(error)")
        }
    }

    func deleteAudio(for recording: Recording) {
        guard let url = recording.fileURL else { return }
        do {
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        } catch {
            print("Failed to delete audio file: \(error)")
        }
    }

    static func recordingsDirectory(fileManager: FileManager = .default) -> URL {
        RecordingStore.baseDirectory(fileManager: fileManager)
            .appendingPathComponent(Constants.recordingsDirectoryName, isDirectory: true)
    }

    static func audioURL(for id: UUID, fileManager: FileManager = .default) -> URL {
        recordingsDirectory(fileManager: fileManager).appendingPathComponent("\(id.uuidString).m4a")
    }

    func destinationURL(for id: UUID) -> URL {
        RecordingStore.audioURL(for: id, fileManager: fileManager)
    }

    func reset() {
        do {
            if fileManager.fileExists(atPath: storeURL.path) {
                try fileManager.removeItem(at: storeURL)
            }
        } catch {
            print("Failed to clear recordings store: \(error)")
        }

        let directory = RecordingStore.recordingsDirectory(fileManager: fileManager)
        if fileManager.fileExists(atPath: directory.path) {
            do {
                try fileManager.removeItem(at: directory)
            } catch {
                print("Failed to remove recordings directory: \(error)")
            }
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    private static func baseDirectory(fileManager: FileManager = .default) -> URL {
        #if os(macOS)
        if let applicationSupport = try? fileManager.url(for: .applicationSupportDirectory,
                                                         in: .userDomainMask,
                                                         appropriateFor: nil,
                                                         create: true) {
            let bundleID = Bundle.main.bundleIdentifier ?? "SwiftTranscriptionAudioApp"
            let directory = applicationSupport.appendingPathComponent(bundleID, isDirectory: true)
            if !fileManager.fileExists(atPath: directory.path) {
                try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            return directory
        }
        #endif
        return fileManager.urls(for: .documentDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
    }
}
