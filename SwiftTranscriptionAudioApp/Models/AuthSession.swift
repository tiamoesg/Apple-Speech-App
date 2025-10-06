import Foundation

struct AuthSession: Codable, Equatable {
    enum ValidationError: LocalizedError {
        case missingUserID
        case missingAPIKey
        case invalidBaseURL

        var errorDescription: String? {
            switch self {
            case .missingUserID:
                return "User ID is required."
            case .missingAPIKey:
                return "API Key is required."
            case .invalidBaseURL:
                return "Enter a valid knowledge base URL."
            }
        }
    }

    let knowledgeBaseBaseURLString: String
    let knowledgeBaseAPIKey: String
    let knowledgeBaseUserID: String
    let megaEmail: String?
    let megaPassword: String?

    static let keychainService = "com.apple.swifttranscription.session"
    static let keychainAccount = "AuthenticatedUserSession"

    var knowledgeBaseBaseURL: URL? {
        URL(string: knowledgeBaseBaseURLString)
    }

    static func make(userID: String,
                     apiKey: String,
                     baseURL: String,
                     megaEmail: String?,
                     megaPassword: String?) throws -> AuthSession {
        let trimmedUserID = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUserID.isEmpty else { throw ValidationError.missingUserID }

        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAPIKey.isEmpty else { throw ValidationError.missingAPIKey }

        let trimmedBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let normalizedURL = URL(string: trimmedBaseURL),
              !normalizedURL.absoluteString.isEmpty,
              normalizedURL.scheme != nil else { throw ValidationError.invalidBaseURL }

        var sanitizedMegaEmail = megaEmail?.trimmingCharacters(in: .whitespacesAndNewlines)
        if sanitizedMegaEmail?.isEmpty ?? true {
            sanitizedMegaEmail = nil
        }

        var sanitizedMegaPassword = megaPassword?.trimmingCharacters(in: .whitespacesAndNewlines)
        if sanitizedMegaPassword?.isEmpty ?? true {
            sanitizedMegaPassword = nil
        }

        if (sanitizedMegaEmail == nil) != (sanitizedMegaPassword == nil) {
            sanitizedMegaEmail = nil
            sanitizedMegaPassword = nil
        }

        return AuthSession(knowledgeBaseBaseURLString: normalizedURL.absoluteString,
                           knowledgeBaseAPIKey: trimmedAPIKey,
                           knowledgeBaseUserID: trimmedUserID,
                           megaEmail: sanitizedMegaEmail,
                           megaPassword: sanitizedMegaPassword)
    }
}
