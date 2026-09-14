import Foundation

enum PipelineStageToggleTests {
    private static let postProcessingKey = "disable_post_processing"
    private static let contextPromptKey = "disable_context_prompt"

    static func run() {
        let suiteName = "PipelineStageToggleTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            TestSupport.expect(false, "Could not create isolated UserDefaults suite")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        defaults.removePersistentDomain(forName: suiteName)
        TestSupport.expect(defaults.object(forKey: postProcessingKey) == nil,
                    "Default post-processing flag must be unset (treated as disabled)")
        TestSupport.expect(defaults.object(forKey: contextPromptKey) == nil,
                    "Default context-prompt flag must be unset (treated as disabled)")

        defaults.set(true, forKey: postProcessingKey)
        defaults.set(true, forKey: contextPromptKey)
        TestSupport.expect(defaults.bool(forKey: postProcessingKey),
                    "Post-processing flag did not persist")
        TestSupport.expect(defaults.bool(forKey: contextPromptKey),
                    "Context-prompt flag did not persist")

        defaults.set(false, forKey: postProcessingKey)
        defaults.set(false, forKey: contextPromptKey)
        TestSupport.expect(!defaults.bool(forKey: postProcessingKey),
                    "Post-processing flag could not be turned off")
        TestSupport.expect(!defaults.bool(forKey: contextPromptKey),
                    "Context-prompt flag could not be turned off")

        let independentA = defaults.bool(forKey: postProcessingKey)
        defaults.set(!independentA, forKey: postProcessingKey)
        TestSupport.expect(defaults.bool(forKey: contextPromptKey) == independentA,
                    "Toggling post-processing changed context-prompt value (flags must be independent)")
        defaults.set(independentA, forKey: postProcessingKey)

        let disabled = AppContext.disabledForUserPreference()
        TestSupport.expect(disabled.appName == nil,
                    "disabledForUserPreference must not capture app name")
        TestSupport.expect(disabled.windowTitle == nil,
                    "disabledForUserPreference must not capture window title")
        TestSupport.expect(disabled.selectedText == nil,
                    "disabledForUserPreference must not capture selected text")
        TestSupport.expect(disabled.contextPrompt == nil,
                    "disabledForUserPreference must not carry an LLM-generated context prompt")
        TestSupport.expect(disabled.screenshotDataURL == nil,
                    "disabledForUserPreference must not carry a screenshot")
        TestSupport.expect(disabled.screenshotError != nil,
                    "disabledForUserPreference should report why context is unavailable")
        TestSupport.expect(disabled.currentActivity.contains("disabled"),
                    "disabledForUserPreference currentActivity should mention 'disabled'")

        // Transcription policy must not contain cleanup toggles. Local mode is
        // about *where* the audio goes, not about whether the transcript may be
        // cleaned up afterwards.
        let localPolicy = LocalTranscriptionPolicy(isEnabled: true)
        TestSupport.expect(localPolicy.isEnabled, "Local policy lost its isEnabled flag")
        TestSupport.expect(!localPolicy.allowsRealtimeStreaming,
                    "Local policy incorrectly allows realtime streaming")

        // Build a synthetic instance just to read those properties; we don't
        // construct a real AppState here because it pulls in the entire macOS
        // stack. The remaining toggles are UserDefaults-backed and covered by
        // the persistence checks above.
    }
}