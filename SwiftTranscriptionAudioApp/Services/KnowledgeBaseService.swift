import Foundation

/// Handles authenticated calls to the DigitalOcean-hosted knowledge base APIs.
/// The service submits transcript payloads for storage/sync and exposes
/// submission metadata so the UI can reflect remote state.
actor KnowledgeBaseService {
    struct Configuration: Sendable {
        let baseURL: URL
        let apiKey: String
        let userID: String
        let transcriptsPath: String
        let additionalHeaders: [String: String]

        init(baseURL: URL,
             apiKey: String,
             userID: String,
             transcriptsPath: String = "/transcripts",
             additionalHeaders: [String: String] = [:]) {
            self.baseURL = baseURL
            self.apiKey = apiKey
            self.userID = userID
            self.transcriptsPath = transcriptsPath
            self.additionalHeaders = additionalHeaders
        }

        init?(environment: [String: String] = ProcessInfo.processInfo.environment) {
            guard let baseURLString = environment["KB_API_BASE_URL"] ?? environment["KBAgentBaseURL"],
                  let url = URL(string: baseURLString) else {
                return nil
            }

            guard let apiKey = environment["KB_API_KEY"] ?? environment["KBAgentAPIKey"],
                  !apiKey.isEmpty else {
                return nil
            }

            guard let userID = environment["KB_USER_ID"] ?? environment["KBAgentUserID"],
                  !userID.isEmpty else {
                return nil
            }

            let transcriptsPath = environment["KB_API_TRANSCRIPTS_PATH"] ?? "/transcripts"
            var headers: [String: String] = [:]
            if let extraHeadersJSON = environment["KB_API_EXTRA_HEADERS"],
               let data = extraHeadersJSON.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
                headers = object
            }

            self.init(baseURL: url,
                      apiKey: apiKey,
                      userID: userID,
                      transcriptsPath: transcriptsPath,
                      additionalHeaders: headers)
        }
    }

    enum ServiceError: Error, LocalizedError {
        case unauthorized
        case invalidResponse
        case serverError(statusCode: Int, message: String?)
        case decodingFailed
        case unableToCreateRequest

        var errorDescription: String? {
            switch self {
            case .unauthorized:
                return "Knowledge base API rejected the request."
            case .invalidResponse:
                return "Received an unexpected response from the knowledge base API."
            case .serverError(let statusCode, let message):
                if let message {
                    return "Knowledge base API error (\(statusCode)): \(message)"
                }
                return "Knowledge base API error (status code \(statusCode))."
            case .decodingFailed:
                return "Unable to decode knowledge base API response."
            case .unableToCreateRequest:
                return "Failed to construct knowledge base API request."
            }
        }
    }

    struct SubmissionResult: Sendable {
        let identifiers: [String]
        let status: String?
        let rawResponse: Data?
    }

    struct TranscriptSubmission: Encodable, Sendable {
        struct MetadataPayload: Encodable, Sendable {
            let recordingTitle: String
            let recordingUpdatedAt: Date
            let appendedSegment: String?
            let knowledgeBaseStatus: String
            let knowledgeBaseIdentifiers: [String]
            let knowledgeBaseLastSyncedAt: Date?
            let knowledgeBaseLastAttemptedAt: Date?
            let knowledgeBaseLastError: String?
            let knowledgeBaseLastKnownRemoteStatus: String?
            let appRecordingID: String
            let appFileURL: String?
        }

        var id: UUID
        var userID: String?
        var fileName: String?
        var transcriptionText: String
        var speaker: Int?
        var createdAt: Date
        var processed: Bool
        var metadata: MetadataPayload
        var fileSize: Int64
        var duration: TimeInterval
        var sourcePath: String?
        var mp3Path: String?
        var confidenceScore: Double?
        var languageDetected: String?
        var tags: [String]

        enum CodingKeys: String, CodingKey {
            case id
            case userID = "user_id"
            case fileName = "file_name"
            case transcriptionText = "transcription_text"
            case speaker
            case createdAt = "created_at"
            case processed
            case metadata
            case fileSize = "file_size"
            case duration
            case sourcePath = "source_path"
            case mp3Path = "mp3_path"
            case confidenceScore = "confidence_score"
            case languageDetected = "language_detected"
            case tags
        }
    }

    private let configuration: Configuration
    private let urlSession: URLSession

    init(configuration: Configuration, urlSession: URLSession = .shared) {
        self.configuration = configuration
        self.urlSession = urlSession
    }

    static func makeDefault(environment: [String: String] = ProcessInfo.processInfo.environment) -> KnowledgeBaseService? {
        guard let configuration = Configuration(environment: environment) else { return nil }
        return KnowledgeBaseService(configuration: configuration)
    }

    func submitTranscript(_ submission: TranscriptSubmission) async throws -> SubmissionResult {
        var payload = submission
        if payload.userID == nil {
            payload.userID = configuration.userID
        }

        guard let request = makeRequest(for: configuration.transcriptsPath,
                                        method: "POST",
                                        payload: payload) else {
            throw ServiceError.unableToCreateRequest
        }

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ServiceError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200..<300:
            return parseResult(from: data)
        case 401, 403:
            throw ServiceError.unauthorized
        default:
            let message = String(data: data, encoding: .utf8)
            throw ServiceError.serverError(statusCode: httpResponse.statusCode, message: message)
        }
    }

    private func makeRequest<T: Encodable>(for path: String,
                                           method: String,
                                           payload: T) -> URLRequest? {
        let normalizedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard let url = URL(string: normalizedPath, relativeTo: configuration.baseURL) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        configuration.additionalHeaders.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(payload) else { return nil }
        request.httpBody = data
        return request
    }

    private func parseResult(from data: Data?) -> SubmissionResult {
        guard let data, !data.isEmpty else {
            return SubmissionResult(identifiers: [], status: nil, rawResponse: nil)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) else {
            return SubmissionResult(identifiers: [], status: nil, rawResponse: data)
        }

        var identifiers: [String] = []
        var status: String?

        func collectIdentifiers(from value: Any) {
            if let dictionary = value as? [String: Any] {
                for (key, nestedValue) in dictionary {
                    if key.lowercased().contains("id"),
                       let stringValue = nestedValue as? String {
                        identifiers.append(stringValue)
                    } else if key.lowercased() == "status",
                              let stringValue = nestedValue as? String {
                        status = stringValue
                    }
                    collectIdentifiers(from: nestedValue)
                }
            } else if let array = value as? [Any] {
                array.forEach { collectIdentifiers(from: $0) }
            }
        }

        collectIdentifiers(from: json)
        identifiers = Array(Set(identifiers))

        return SubmissionResult(identifiers: identifiers, status: status, rawResponse: data)
    }
}
