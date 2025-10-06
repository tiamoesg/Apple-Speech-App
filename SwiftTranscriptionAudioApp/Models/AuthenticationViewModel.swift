import Foundation

@MainActor
final class AuthenticationViewModel: ObservableObject {
    @Published private(set) var session: AuthSession?
    @Published var isProcessing = false
    @Published var errorMessage: String?

    init() {
        session = AuthenticationViewModel.loadSessionFromKeychain()
    }

    func login(with credentials: LoginCredentials) async {
        errorMessage = nil
        isProcessing = true
        defer { isProcessing = false }

        do {
            let newSession = try AuthSession.make(from: credentials)
            let encoder = JSONEncoder()
            let data = try encoder.encode(newSession)
            try KeychainStorage.store(data,
                                      service: AuthSession.keychainService,
                                      account: AuthSession.keychainAccount)
            session = newSession
        } catch {
            if let error = error as? LocalizedError {
                errorMessage = error.errorDescription
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    func logout(currentStoryModel: StoryModel?) {
        currentStoryModel?.reset()
        try? KeychainStorage.delete(service: AuthSession.keychainService,
                                    account: AuthSession.keychainAccount)
        session = nil
    }

    func defaultKnowledgeBaseURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        if let url = environment["KB_API_BASE_URL"] ?? environment["KBAgentBaseURL"], !url.isEmpty {
            return url
        }
        return "https://"
    }

    private static func loadSessionFromKeychain() -> AuthSession? {
        guard let data = try? KeychainStorage.load(service: AuthSession.keychainService,
                                                   account: AuthSession.keychainAccount) else {
            return nil
        }

        guard let data else { return nil }
        return try? JSONDecoder().decode(AuthSession.self, from: data)
    }
}
