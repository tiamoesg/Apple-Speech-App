/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
App initializer
*/

import SwiftUI
import SwiftData

@main
struct SwiftTranscriptionAudioApp: App {
    @StateObject private var authViewModel = AuthenticationViewModel()

    var body: some Scene {
        WindowGroup {
            Group {
                if let session = authViewModel.session {
                    AuthenticatedSessionView(session: session)
                } else {
                    LoginView()
                }
            }
            .environmentObject(authViewModel)
        }
    }
}

private struct AuthenticatedSessionView: View {
    let session: AuthSession
    @StateObject private var storyModel: StoryModel

    init(session: AuthSession) {
        self.session = session
        _storyModel = StateObject(wrappedValue: StoryModel(session: session))
    }

    var body: some View {
        ContentView(viewModel: storyModel)
            .id(session.knowledgeBaseUserID)
    }
}
