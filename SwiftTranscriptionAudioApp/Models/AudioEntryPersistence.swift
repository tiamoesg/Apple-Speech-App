import Foundation

struct AudioEntryPersistence {
    private enum Constants {
        static let storeFileName = "recordings.json"
        static let recordingsDirectoryName = "Recordings"
    }

    private let storeURL: URL
    private let recordingsDirectoryURL: URL

    init(fileManager: FileManager = .default) {
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
        self.recordingsDirectoryURL = documentsDirectory.appendingPathComponent(Constants.recordingsDirectoryName, isDirectory: true)
        self.storeURL = documentsDirectory.appendingPathComponent(Constants.storeFileName)

        if !fileManager.fileExists(atPath: recordingsDirectoryURL.path) {
            try? fileManager.createDirectory(at: recordingsDirectoryURL, withIntermediateDirectories: true)
        }
    }

    func load() -> [AudioEntry] {
        guard let data = try? Data(contentsOf: storeURL) else { return [] }

        do {
            let persisted = try JSONDecoder().decode([PersistedAudioEntry].self, from: data)
            return persisted.compactMap { $0.makeAudioEntry(baseDirectory: recordingsDirectoryURL) }
        } catch {
            print("Failed to load recordings: \(error)")
            return []
        }
    }

    func save(_ audioEntries: [AudioEntry]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]

        let persisted = audioEntries.map { PersistedAudioEntry(audioEntry: $0, baseDirectory: recordingsDirectoryURL) }

        do {
            let data = try encoder.encode(persisted)
            try data.write(to: storeURL, options: .atomic)
        } catch {
            print("Failed to persist recordings: \(error)")
        }
    }

    func persistAudio(for audioEntry: AudioEntry) {
        guard let url = audioEntry.url else { return }
        let destination = audioURL(for: audioEntry.id)
        let fileManager = FileManager.default

        do {
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            if url != destination {
                try fileManager.moveItem(at: url, to: destination)
                audioEntry.url = destination
            }
        } catch {
            print("Failed to persist audio file: \(error)")
        }
    }

    func deleteAudio(for audioEntry: AudioEntry) {
        guard let url = audioEntry.url else { return }
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        } catch {
            print("Failed to delete audio file: \(error)")
        }
    }

    func audioURL(for id: UUID) -> URL {
        recordingsDirectoryURL.appendingPathComponent("\(id.uuidString).wav")
    }
}

private struct PersistedAudioEntry: Codable {
    var id: UUID
    var title: String
    var textData: Data
    var audioFileName: String?
    var isDone: Bool
    var createdAt: Date
    var isOffloaded: Bool

    init(audioEntry: AudioEntry, baseDirectory: URL) {
        self.id = audioEntry.id
        self.title = audioEntry.title
        let nsAttributed = NSAttributedString(audioEntry.text)
        self.textData = (try? NSKeyedArchiver.archivedData(withRootObject: nsAttributed, requiringSecureCoding: true)) ?? Data()
        self.audioFileName = audioEntry.url?.lastPathComponent
        self.isDone = audioEntry.isDone
        self.createdAt = audioEntry.createdAt
        self.isOffloaded = audioEntry.isOffloaded
    }

    func makeAudioEntry(baseDirectory: URL) -> AudioEntry? {
        guard let nsAttributed = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSAttributedString.self, from: textData) else { return nil }
        let audioEntry = AudioEntry(id: id,
                                     title: title,
                                     text: AttributedString(nsAttributed),
                                     url: audioFileName.map { baseDirectory.appendingPathComponent($0) },
                                     isDone: isDone,
                                     createdAt: createdAt,
                                     isOffloaded: isOffloaded)
        return audioEntry
    }
}
