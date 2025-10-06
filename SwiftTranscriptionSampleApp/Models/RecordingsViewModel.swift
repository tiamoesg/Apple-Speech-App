import Foundation
import SwiftUI

@MainActor
final class RecordingsViewModel: ObservableObject {
    @Published private(set) var stories: [Story] = []
    @Published var activeSheet: Story?

    private let persistence: StoryPersistence
    private var playbackRecorder: Recorder?
    private var playbackTranscriber: SpokenWordTranscriber?
    private(set) var currentlyPlayingStoryID: UUID?

    init(persistence: StoryPersistence = StoryPersistence()) {
        self.persistence = persistence
        loadPersistedStories()
    }

    func loadPersistedStories() {
        stories = persistence.load().sorted(by: { $0.createdAt > $1.createdAt })
    }

    func createStory() -> Story {
        let story = Story.blank()
        story.createdAt = Date()
        stories.insert(story, at: 0)
        persistence.save(stories)
        activeSheet = story
        return story
    }

    func binding(for story: Story) -> Binding<Story>? {
        guard let index = stories.firstIndex(where: { $0.id == story.id }) else { return nil }
        return Binding(get: { self.stories[index] }, set: { newValue in
            self.stories[index] = newValue
            self.persistence.save(self.stories)
        })
    }

    func persist(_ story: Story) {
        guard let index = stories.firstIndex(where: { $0.id == story.id }) else { return }

        objectWillChange.send()

        if story.url != nil {
            persistence.persistAudio(for: story)
            story.isOffloaded = false
        }

        stories[index] = story
        stories.sort(by: { $0.createdAt > $1.createdAt })
        persistence.save(stories)
    }

    func delete(_ story: Story) {
        guard let index = stories.firstIndex(where: { $0.id == story.id }) else { return }

        stopPlayback()
        persistence.deleteAudio(for: story)
        stories.remove(at: index)
        if activeSheet?.id == story.id {
            activeSheet = nil
        }
        persistence.save(stories)
    }

    func offload(_ story: Story) {
        guard let index = stories.firstIndex(where: { $0.id == story.id }) else { return }

        stopPlayback()
        persistence.deleteAudio(for: story)
        objectWillChange.send()
        stories[index].url = nil
        stories[index].isOffloaded = true
        persistence.save(stories)
    }

    func togglePlayback(for story: Story) {
        if currentlyPlayingStoryID == story.id {
            stopPlayback()
        } else {
            startPlayback(for: story)
        }
    }

    private func startPlayback(for story: Story) {
        guard let url = story.url, FileManager.default.fileExists(atPath: url.path) else { return }

        stopPlayback()

        guard let binding = binding(for: story) else { return }
        let transcriber = SpokenWordTranscriber(story: binding)
        let recorder = Recorder(transcriber: transcriber, story: binding)
        recorder.prepareForPlayback(with: url)
        recorder.playRecording()

        objectWillChange.send()
        story.isPlaying = true
        playbackRecorder = recorder
        playbackTranscriber = transcriber
        currentlyPlayingStoryID = story.id
    }

    func stopPlayback() {
        playbackRecorder?.stopPlaying()
        playbackRecorder = nil
        playbackTranscriber = nil

        if let id = currentlyPlayingStoryID,
           let index = stories.firstIndex(where: { $0.id == id }) {
            objectWillChange.send()
            stories[index].isPlaying = false
        }

        currentlyPlayingStoryID = nil
    }
}
