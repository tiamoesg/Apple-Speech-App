import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var authViewModel: AuthenticationViewModel
    @State private var knowledgeBaseURL: String = ""
    @State private var knowledgeBaseAPIKey: String = ""
    @State private var knowledgeBaseUserID: String = ""
    @State private var useMegaStorage = false
    @State private var megaEmail: String = ""
    @State private var megaPassword: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Knowledge Base"),
                        footer: Text("Provide the API credentials that allow transcripts to sync to your knowledge base.")) {
                    TextField("Base URL", text: $knowledgeBaseURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    SecureField("API Key", text: $knowledgeBaseAPIKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    TextField("User ID", text: $knowledgeBaseUserID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section(header: Toggle(isOn: $useMegaStorage.animation()) {
                    Text("Use MEGA for remote storage")
                }) {
                    if useMegaStorage {
                        TextField("MEGA Email", text: $megaEmail)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        SecureField("MEGA Password", text: $megaPassword)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } else {
                        Text("Audio files remain on-device when MEGA is disabled.")
                            .foregroundStyle(.secondary)
                    }
                }

                if let errorMessage = authViewModel.errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Sign In")
            .toolbar {
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
        .onAppear {
            if knowledgeBaseURL.isEmpty {
                knowledgeBaseURL = authViewModel.defaultKnowledgeBaseURL()
            }
        }
    }

    private func signIn() {
        Task {
            await authViewModel.login(userID: knowledgeBaseUserID,
                                      apiKey: knowledgeBaseAPIKey,
                                      baseURL: knowledgeBaseURL,
                                      megaEmail: useMegaStorage ? megaEmail : nil,
                                      megaPassword: useMegaStorage ? megaPassword : nil)
        }
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthenticationViewModel())
}
