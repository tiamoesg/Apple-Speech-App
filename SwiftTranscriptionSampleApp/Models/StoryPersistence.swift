import Foundation

struct StoryPersistence {
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

    func load() -> [Story] {
        guard let data = try? Data(contentsOf: storeURL) else { return [] }

        do {
            let persisted = try JSONDecoder().decode([PersistedStory].self, from: data)
            return persisted.compactMap { $0.makeStory(baseDirectory: recordingsDirectoryURL) }
        } catch {
            print("Failed to load recordings: \(error)")
            return []
        }
    }

    func save(_ stories: [Story]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]

        let persisted = stories.map { PersistedStory(story: $0, baseDirectory: recordingsDirectoryURL) }

        do {
            let data = try encoder.encode(persisted)
            try data.write(to: storeURL, options: .atomic)
        } catch {
            print("Failed to persist recordings: \(error)")
        }
    }

    func persistAudio(for story: Story) {
        guard let url = story.url else { return }
        let destination = audioURL(for: story.id)
        let fileManager = FileManager.default

        do {
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            if url != destination {
                try fileManager.moveItem(at: url, to: destination)
                story.url = destination
            }
        } catch {
            print("Failed to persist audio file: \(error)")
        }
    }

    func deleteAudio(for story: Story) {
        guard let url = story.url else { return }
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

private struct PersistedStory: Codable {
    var id: UUID
    var title: String
    var textData: Data
    var audioFileName: String?
    var isDone: Bool
    var createdAt: Date
    var isOffloaded: Bool

    init(story: Story, baseDirectory: URL) {
        self.id = story.id
        self.title = story.title
        let nsAttributed = NSAttributedString(story.text)
        self.textData = (try? NSKeyedArchiver.archivedData(withRootObject: nsAttributed, requiringSecureCoding: true)) ?? Data()
        self.audioFileName = story.url?.lastPathComponent
        self.isDone = story.isDone
        self.createdAt = story.createdAt
        self.isOffloaded = story.isOffloaded
    }

    func makeStory(baseDirectory: URL) -> Story? {
        guard let nsAttributed = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSAttributedString.self, from: textData) else { return nil }
        let story = Story(id: id,
                          title: title,
                          text: AttributedString(nsAttributed),
                          url: audioFileName.map { baseDirectory.appendingPathComponent($0) },
                          isDone: isDone,
                          createdAt: createdAt,
                          isOffloaded: isOffloaded)
        return story
    }
}
