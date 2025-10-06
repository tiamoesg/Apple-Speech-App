import Foundation

struct LoginCredentials {
    struct KnowledgeBase {
        let baseURL: String
        let apiKey: String
        let userID: String
    }

    struct Mega {
        let email: String?
        let password: String?

        var isConfigured: Bool {
            email != nil && password != nil
        }
    }

    let knowledgeBase: KnowledgeBase
    let mega: Mega

    init(knowledgeBaseURL: String,
         apiKey: String,
         userID: String,
         megaEmail: String?,
         megaPassword: String?) {
        let trimmedURL = knowledgeBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUserID = userID.trimmingCharacters(in: .whitespacesAndNewlines)

        let sanitizedEmail = megaEmail?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let sanitizedPassword = megaPassword?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty

        let megaCredentials: Mega
        if sanitizedEmail == nil || sanitizedPassword == nil {
            megaCredentials = Mega(email: nil, password: nil)
        } else {
            megaCredentials = Mega(email: sanitizedEmail, password: sanitizedPassword)
        }

        self.knowledgeBase = KnowledgeBase(baseURL: trimmedURL,
                                           apiKey: trimmedAPIKey,
                                           userID: trimmedUserID)
        self.mega = megaCredentials
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
