/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
AUDIO entry data model.
*/

import Foundation
import AVFoundation
import FoundationModels

@Observable
class AudioEntry: Identifiable {
    typealias StartTime = CMTime

    let id: UUID
    var title: String
    var text: AttributedString
    var url: URL?
    var isDone: Bool
    var createdAt: Date
    var isOffloaded: Bool
    var isPlaying: Bool = false

    init(id: UUID = UUID(),
         title: String,
         text: AttributedString,
         url: URL? = nil,
         isDone: Bool = false,
         createdAt: Date = Date(),
         isOffloaded: Bool = false) {
        self.id = id
        self.title = title
        self.text = text
        self.url = url
        self.isDone = isDone
        self.createdAt = createdAt
        self.isOffloaded = isOffloaded
    }
    
    func suggestedTitle() async throws -> String? {
        guard SystemLanguageModel.default.isAvailable else { return nil }
        let session = LanguageModelSession(model: SystemLanguageModel.default)
        let answer = try await session.respond(to: "Here is a children's story. Can you please return your very best suggested title for it, with no other text? The title should be descriptive of the story and include the main character's name. Story: \(text.characters)")
        return answer.content.trimmingCharacters(in: .punctuationCharacters)
    }
}

extension AudioEntry {
    static func blankAudioEntry() -> AudioEntry {
        return .init(title: "New AUDIO", text: AttributedString(""))
    }

    func audioTranscriptBrokenUpByLines() -> AttributedString {
        print(String(text.characters))
        if url == nil {
            print("url was nil")
            return text
        } else {
            var final = AttributedString("")
            var working = AttributedString("")
            let copy = text
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
}

// MARK: - Persistence

extension Story: Codable {
    enum CodingKeys: String, CodingKey {
        case id
        case title
        case textData
        case url
        case isDone
        case createdAt
        case isOffloaded
    }

    convenience init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(UUID.self, forKey: .id)
        let title = try container.decode(String.self, forKey: .title)
        let textData = try container.decode(Data.self, forKey: .textData)
        let nsAttributed = try NSKeyedUnarchiver.unarchivedObject(ofClass: NSAttributedString.self, from: textData) ?? NSAttributedString()
        let text = AttributedString(nsAttributed)
        let url = try container.decodeIfPresent(URL.self, forKey: .url)
        let isDone = try container.decode(Bool.self, forKey: .isDone)
        let createdAt = try container.decode(Date.self, forKey: .createdAt)
        let isOffloaded = try container.decode(Bool.self, forKey: .isOffloaded)

        self.init(id: id,
                  title: title,
                  text: text,
                  url: url,
                  isDone: isDone,
                  createdAt: createdAt,
                  isOffloaded: isOffloaded)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        let nsAttributed = NSAttributedString(text)
        let data = try NSKeyedArchiver.archivedData(withRootObject: nsAttributed, requiringSecureCoding: true)
        try container.encode(data, forKey: .textData)
        try container.encodeIfPresent(url, forKey: .url)
        try container.encode(isDone, forKey: .isDone)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(isOffloaded, forKey: .isOffloaded)
    }
}

extension Story {
    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    var fileSizeDescription: String {
        guard let url, FileManager.default.fileExists(atPath: url.path) else {
            return isOffloaded ? "Offloaded" : "--"
        }

        do {
            let resources = try url.resourceValues(forKeys: [.fileSizeKey])
            guard let size = resources.fileSize else { return "--" }
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useKB, .useMB]
            formatter.countStyle = .file
            return formatter.string(fromByteCount: Int64(size))
        } catch {
            return "--"
        }
    }

    var formattedTimestamp: String {
        Story.timestampFormatter.string(from: createdAt)
    }
}
