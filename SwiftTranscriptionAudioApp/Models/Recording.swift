import Foundation
import AVFoundation
import FoundationModels

@Observable
final class Recording: Identifiable, Codable {
    enum CodingKeys: String, CodingKey {
        case id
        case title
        case transcriptData
        case filePath
        case isComplete
        case createdAt
        case updatedAt
        case isOffloaded
        case duration
        case fileSize
        case megaNodeHandle
        case metadata
    }

    let id: UUID
    var title: String
    var transcript: AttributedString
    var fileURL: URL?
    var isComplete: Bool
    var createdAt: Date
    var updatedAt: Date
    var isOffloaded: Bool
    var megaNodeHandle: UInt64?
    var duration: TimeInterval
    var fileSize: Int64
    var metadata: Metadata
    var isPlaying: Bool = false
    var isOffloading: Bool = false

    struct Metadata: Codable, Sendable {
        var knowledgeBaseSync: KnowledgeBaseSync

        init(knowledgeBaseSync: KnowledgeBaseSync = KnowledgeBaseSync()) {
            self.knowledgeBaseSync = knowledgeBaseSync
        }

        func updatingKnowledgeBaseSync(_ update: (inout KnowledgeBaseSync) -> Void) -> Metadata {
            var copy = self
            update(&copy.knowledgeBaseSync)
            return copy
        }
    }

    struct KnowledgeBaseSync: Codable, Sendable {
        enum Status: String, Codable, Sendable {
            case idle
            case pending
            case success
            case error
        }

        var status: Status
        var remoteIdentifiers: [String]
        var lastErrorMessage: String?
        var lastSyncedAt: Date?
        var lastAttemptedAt: Date?
        var lastKnownRemoteStatus: String?

        init(status: Status = .idle,
             remoteIdentifiers: [String] = [],
             lastErrorMessage: String? = nil,
             lastSyncedAt: Date? = nil,
             lastAttemptedAt: Date? = nil,
             lastKnownRemoteStatus: String? = nil) {
            self.status = status
            self.remoteIdentifiers = remoteIdentifiers
            self.lastErrorMessage = lastErrorMessage
            self.lastSyncedAt = lastSyncedAt
            self.lastAttemptedAt = lastAttemptedAt
            self.lastKnownRemoteStatus = lastKnownRemoteStatus
        }
    }

    init(id: UUID = UUID(),
         title: String,
         transcript: AttributedString,
         fileURL: URL? = nil,
         isComplete: Bool = false,
         createdAt: Date = Date(),
         updatedAt: Date = Date(),
         isOffloaded: Bool = false,
         megaNodeHandle: UInt64? = nil,
         duration: TimeInterval = 0,
         fileSize: Int64 = 0,
         metadata: Metadata = Metadata()) {
        self.id = id
        self.title = title
        self.transcript = transcript
        self.fileURL = fileURL
        self.isComplete = isComplete
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isOffloaded = isOffloaded
        self.megaNodeHandle = megaNodeHandle
        self.duration = duration
        self.fileSize = fileSize
        self.metadata = metadata
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        let transcriptData = try container.decode(Data.self, forKey: .transcriptData)
        let attributed = try NSKeyedUnarchiver.unarchivedObject(ofClass: NSAttributedString.self, from: transcriptData) ?? NSAttributedString()
        transcript = AttributedString(attributed)
        if let filePath = try container.decodeIfPresent(String.self, forKey: .filePath) {
            let baseURL = RecordingStore.recordingsDirectory()
            fileURL = baseURL.appendingPathComponent(filePath)
        } else {
            fileURL = nil
        }
        isComplete = try container.decode(Bool.self, forKey: .isComplete)
        let decodedCreatedAt = try container.decode(Date.self, forKey: .createdAt)
        let decodedUpdatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? decodedCreatedAt
        createdAt = decodedCreatedAt
        updatedAt = decodedUpdatedAt
        isOffloaded = try container.decode(Bool.self, forKey: .isOffloaded)
        megaNodeHandle = try container.decodeIfPresent(UInt64.self, forKey: .megaNodeHandle)
        duration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration) ?? 0
        fileSize = try container.decodeIfPresent(Int64.self, forKey: .fileSize) ?? 0
        metadata = try container.decodeIfPresent(Metadata.self, forKey: .metadata) ?? Metadata()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        let nsAttributed = NSAttributedString(transcript)
        let data = try NSKeyedArchiver.archivedData(withRootObject: nsAttributed, requiringSecureCoding: true)
        try container.encode(data, forKey: .transcriptData)
        try container.encodeIfPresent(fileURL?.lastPathComponent, forKey: .filePath)
        try container.encode(isComplete, forKey: .isComplete)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(isOffloaded, forKey: .isOffloaded)
        try container.encodeIfPresent(megaNodeHandle, forKey: .megaNodeHandle)
        try container.encode(duration, forKey: .duration)
        try container.encode(fileSize, forKey: .fileSize)
        try container.encode(metadata, forKey: .metadata)
    }

    func suggestedTitle() async throws -> String? {
        guard SystemLanguageModel.default.isAvailable else { return nil }
        let session = LanguageModelSession(model: SystemLanguageModel.default)
        let answer = try await session.respond(to: "Here is an audio transcript. Can you please suggest a concise, descriptive title for it, with no other text? The title should highlight the key subject. Transcript: \(transcript.characters)")
        return answer.content.trimmingCharacters(in: .punctuationCharacters)
    }
}

extension Recording {
    static func blank() -> Recording {
        Recording(title: "New Recording",
                  transcript: AttributedString(""),
                  createdAt: Date(),
                  updatedAt: Date())
    }

    func transcriptSplitBySentences() -> AttributedString {
        guard fileURL != nil else { return transcript }

        var final = AttributedString("")
        var working = AttributedString("")
        let copy = transcript
        copy.runs.forEach { run in
            if copy[run.range].characters.contains(".") {
                working.append(copy[run.range])
                final.append(working)
                final.append(AttributedString("\n\n"))
                working = AttributedString("")
            } else {
                if working.characters.isEmpty {
                    let newText = copy[run.range].characters
                    let attributes = run.attributes
                    let trimmed = newText.trimmingPrefix(" ")
                    let newAttributed = AttributedString(trimmed, attributes: attributes)
                    working.append(newAttributed)
                } else {
                    working.append(copy[run.range])
                }
            }
        }

        if final.characters.isEmpty {
            return working
        }

        return final
    }
}

extension Recording {
    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    var formattedTimestamp: String {
        Recording.timestampFormatter.string(from: createdAt)
    }

    var durationDescription: String {
        guard duration > 0 else { return "--" }
        return Recording.durationFormatter.string(from: duration) ?? "--"
    }

    var fileSizeDescription: String {
        guard fileSize > 0 else { return isOffloaded ? "Offloaded" : "--" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }

    var canStreamRemotely: Bool {
        isOffloaded && megaNodeHandle != nil
    }

    var isPlayable: Bool {
        (fileURL != nil) || canStreamRemotely
    }

    var knowledgeBaseSyncStatus: KnowledgeBaseSync.Status {
        metadata.knowledgeBaseSync.status
    }

    var knowledgeBaseSyncErrorDescription: String? {
        metadata.knowledgeBaseSync.lastErrorMessage
    }

    var knowledgeBaseRemoteIdentifiers: [String] {
        metadata.knowledgeBaseSync.remoteIdentifiers
    }

    var isKnowledgeBaseSyncPending: Bool {
        metadata.knowledgeBaseSync.status == .pending
    }
}
