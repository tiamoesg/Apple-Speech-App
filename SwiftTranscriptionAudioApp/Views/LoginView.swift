import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var authViewModel: AuthenticationViewModel
    @State private var formState = LoginFormState()

    var body: some View {
        NavigationStack {
            Form {
                KnowledgeBaseSection(form: $formState)
                MegaStorageSection(form: $formState)
                ErrorSection(message: authViewModel.errorMessage)
            }
            .navigationTitle("Sign In")
            .toolbar { toolbarContent }
        }
        .onAppear(perform: populateDefaults)
    }

    private func populateDefaults() {
        formState.applyDefaultsIfNeeded(session: authViewModel.session,
                                        defaultBaseURL: authViewModel.defaultKnowledgeBaseURL())
    }

    private func signIn() {
        let credentials = formState.makeCredentials()
        Task {
            await authViewModel.login(with: credentials)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Button(action: signIn) {
                if authViewModel.isProcessing {
                    ProgressView()
                } else {
                    Text("Continue")
                }
            }
            .disabled(authViewModel.isProcessing)
        }
    }
}

private struct KnowledgeBaseSection: View {
    @Binding var form: LoginFormState

    var body: some View {
        Section {
            TextField("Base URL", text: $form.knowledgeBaseURL)
#if canImport(UIKit)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
#endif
                .autocorrectionDisabled()

            SecureField("API Key", text: $form.knowledgeBaseAPIKey)
#if canImport(UIKit)
                .textInputAutocapitalization(.never)
#endif
                .autocorrectionDisabled()

            TextField("User ID", text: $form.knowledgeBaseUserID)
#if canImport(UIKit)
                .textInputAutocapitalization(.never)
#endif
                .autocorrectionDisabled()
        } header: {
            Text("Knowledge Base")
        } footer: {
            Text("Provide the API credentials that allow transcripts to sync to your knowledge base.")
        }
    }
}

private struct MegaStorageSection: View {
    @Binding var form: LoginFormState

    var body: some View {
        Section {
            Toggle("Use MEGA for remote storage", isOn: $form.useMegaStorage.animation())

            if form.useMegaStorage {
                TextField("MEGA Email", text: $form.megaEmail)
#if canImport(UIKit)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
#endif
                    .autocorrectionDisabled()

                SecureField("MEGA Password", text: $form.megaPassword)
#if canImport(UIKit)
                    .textInputAutocapitalization(.never)
#endif
                    .autocorrectionDisabled()
            } else {
                Text("Audio files remain on-device when MEGA is disabled.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Remote Storage")
        }
    }
}

private struct ErrorSection: View {
    let message: String?

    var body: some View {
        if let message {
            Section {
                Text(message)
                    .foregroundStyle(.red)
            }
        }
    }
}

private struct LoginFormState {
    var knowledgeBaseURL: String = ""
    var knowledgeBaseAPIKey: String = ""
    var knowledgeBaseUserID: String = ""

    var useMegaStorage: Bool = false
    var megaEmail: String = ""
    var megaPassword: String = ""

    mutating func applyDefaultsIfNeeded(session: AuthSession?, defaultBaseURL: String) {
        if let session {
            if knowledgeBaseURL.isEmpty { knowledgeBaseURL = session.knowledgeBaseBaseURLString }
            if knowledgeBaseAPIKey.isEmpty { knowledgeBaseAPIKey = session.knowledgeBaseAPIKey }
            if knowledgeBaseUserID.isEmpty { knowledgeBaseUserID = session.knowledgeBaseUserID }

            if let email = session.megaEmail, let password = session.megaPassword {
                useMegaStorage = true
                if megaEmail.isEmpty { megaEmail = email }
                if megaPassword.isEmpty { megaPassword = password }
            }
        } else if knowledgeBaseURL.isEmpty {
            knowledgeBaseURL = defaultBaseURL
        }
    }

    func makeCredentials() -> LoginCredentials {
        LoginCredentials(knowledgeBaseURL: knowledgeBaseURL,
                         apiKey: knowledgeBaseAPIKey,
                         userID: knowledgeBaseUserID,
                         megaEmail: useMegaStorage ? megaEmail : nil,
                         megaPassword: useMegaStorage ? megaPassword : nil)
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthenticationViewModel())
}
