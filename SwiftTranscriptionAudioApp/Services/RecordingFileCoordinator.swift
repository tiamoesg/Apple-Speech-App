import Foundation

struct RecordingFileCoordinator {
    private enum Constants {
        static let storeFileName = "recordings.json"
        static let recordingsDirectoryName = "Recordings"
    }

    private let fileManager: FileManager

    let baseDirectory: URL
    let storeURL: URL
    let recordingsDirectory: URL

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.baseDirectory = RecordingFileCoordinator.baseDirectory(fileManager: fileManager)
        self.storeURL = baseDirectory.appendingPathComponent(Constants.storeFileName)
        self.recordingsDirectory = baseDirectory.appendingPathComponent(Constants.recordingsDirectoryName,
                                                                         isDirectory: true)
        ensureRecordingsDirectoryExists()
    }

    func audioURL(for id: UUID) -> URL {
        recordingsDirectory.appendingPathComponent("\(id.uuidString).m4a")
    }

    func deleteAudioIfNeeded(at url: URL) {
        guard fileManager.fileExists(atPath: url.path) else { return }

        do {
            try fileManager.removeItem(at: url)
        } catch {
            print("Failed to delete audio file: \(error)")
        }
    }

    func reset() {
        removeStore()
        removeRecordingsDirectory()
        ensureRecordingsDirectoryExists()
    }

    private func ensureRecordingsDirectoryExists() {
        guard !fileManager.fileExists(atPath: recordingsDirectory.path) else { return }
        do {
            try fileManager.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)
        } catch {
            print("Failed to create recordings directory: \(error)")
        }
    }

    private func removeStore() {
        guard fileManager.fileExists(atPath: storeURL.path) else { return }
        do {
            try fileManager.removeItem(at: storeURL)
        } catch {
            print("Failed to clear recordings store: \(error)")
        }
    }

    private func removeRecordingsDirectory() {
        guard fileManager.fileExists(atPath: recordingsDirectory.path) else { return }
        do {
            try fileManager.removeItem(at: recordingsDirectory)
        } catch {
            print("Failed to remove recordings directory: \(error)")
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
