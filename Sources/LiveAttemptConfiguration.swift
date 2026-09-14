import Foundation

/// Pure orchestration helper that turns one captured `ResolvedLanguageProfile`
/// plus the current global toggles into the concrete configuration values
/// the recording pipeline needs for a single Processing Attempt.
///
/// The recording pipeline deliberately captures a `ResolvedLanguageProfile`
/// snapshot at recording start and threads that immutable snapshot through
/// the rest of the attempt. Settings edits during the attempt therefore
/// cannot mix old and new configurations; this helper consumes only the
/// passed-in snapshot and the global toggles, never live settings.
///
/// Extracted as a pure helper so the gating rules can be tested without
/// spinning up the real `AppState`, microphone, audio recorder, or any
/// transcription backend.
enum LiveAttemptConfigurationBuilder {

    /// Which transcription path the attempt should use, decided once from
    /// the global `LocalTranscriptionPolicy` value captured at recording
    /// start. Storing the mode (rather than re-reading the live policy at
    /// transcription time) guarantees that a settings toggle during the
    /// attempt cannot flip a locally-started attempt to an upload one, or
    /// vice versa.
    enum TranscriptionMode: Equatable {
        case local(languageHint: String?)
        case upload(apiKey: String, baseURL: String, model: String, language: String?)
    }

    /// Complete configuration a single recording attempt should use.
    /// `Equatable` so tests can compare two configurations field by field
    /// without inspecting internal types.
    struct Configuration: Equatable {
        /// Profile identity preserved for history / debug surfaces.
        let profileID: UUID
        let profileName: String

        /// Transcription backend the attempt should use. The mode is
        /// decided at recording start from the captured profile plus the
        /// `localPolicy` snapshot, so production never re-reads the live
        /// toggle while the attempt is in flight.
        let transcriptionMode: TranscriptionMode

        /// System prompt the ordinary dictation cleanup should run with.
        /// Edit Mode's command-transform prompt is always its dedicated
        /// prompt and never sees this value.
        let ordinaryCleanupSystemPrompt: String

        /// True when `RealtimeTranscriptionService.start()` should be called
        /// on a fresh service built from `realtimeConfiguration`. False when
        /// the global realtime toggle is off, the local policy does not
        /// permit realtime, or the profile's resolved endpoint is empty.
        let shouldStartRealtime: Bool

        /// Configuration to hand to `RealtimeTranscriptionService` when
        /// `shouldStartRealtime` is true. `nil` otherwise.
        let realtimeConfiguration: RealtimeTranscriptionService.Configuration?
    }

    /// Build the complete configuration for a single recording attempt from
    /// the captured profile snapshot and the current global toggles. Pure:
    /// the same inputs always produce the same outputs, so this is the
    /// testable seam between profile resolution and the recording pipeline.
    ///
    /// - Parameters:
    ///   - resolvedProfile: Immutable snapshot captured at recording start.
    ///   - realtimeStreamingEnabled: Global "Realtime Streaming" toggle.
    ///   - localPolicy: Global on-device transcription policy.
    static func configuration(
        resolvedProfile: ResolvedLanguageProfile,
        realtimeStreamingEnabled: Bool,
        localPolicy: LocalTranscriptionPolicy
    ) -> Configuration {
        // Capture the transcription mode at recording start. Settings
        // edits during the attempt cannot flip a locally-started attempt
        // to an upload one (or vice versa), nor leak endpoint, credential,
        // or model overrides into the local recogniser.
        let transcriptionMode: TranscriptionMode
        if localPolicy.isEnabled {
            transcriptionMode = .local(languageHint: resolvedProfile.languageHint)
        } else {
            transcriptionMode = .upload(
                apiKey: resolvedProfile.transcriptionAPIKey,
                baseURL: resolvedProfile.transcriptionBaseURL,
                model: resolvedProfile.transcriptionModel,
                language: resolvedProfile.languageHint
            )
        }

        let realtime = evaluateRealtime(
            resolvedProfile: resolvedProfile,
            realtimeStreamingEnabled: realtimeStreamingEnabled,
            localPolicy: localPolicy
        )

        return Configuration(
            profileID: resolvedProfile.profileID,
            profileName: resolvedProfile.profileName,
            transcriptionMode: transcriptionMode,
            ordinaryCleanupSystemPrompt: resolvedProfile.ordinaryCleanupSystemPrompt,
            shouldStartRealtime: realtime.shouldStart,
            realtimeConfiguration: realtime.configuration
        )
    }

    /// Decide whether realtime streaming should be configured for this
    /// attempt, and if so build the configuration the realtime service
    /// should run with. The decision honours the global realtime toggle and
    /// the local policy, then uses only the captured profile values — never
    /// live settings — to fill the configuration.
    private static func evaluateRealtime(
        resolvedProfile: ResolvedLanguageProfile,
        realtimeStreamingEnabled: Bool,
        localPolicy: LocalTranscriptionPolicy
    ) -> (shouldStart: Bool, configuration: RealtimeTranscriptionService.Configuration?) {
        // Gating rules (tested directly in LiveAttemptConfigurationTests):
        // 1. Global realtime toggle off → no realtime service regardless
        //    of profile content.
        // 2. Local transcription policy on → no realtime service (local
        //    recogniser emits a finished transcript on stop, not partials).
        // 3. Profile's resolved endpoint empty → no realtime service (no
        //    WebSocket URL can be derived).
        guard realtimeStreamingEnabled, localPolicy.allowsRealtimeStreaming else {
            return (false, nil)
        }
        let trimmedBase = resolvedProfile.transcriptionBaseURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBase.isEmpty else {
            return (false, nil)
        }
        let trimmedModel = resolvedProfile.realtimeModel
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (
            true,
            RealtimeTranscriptionService.Configuration(
                baseURL: trimmedBase,
                apiKey: resolvedProfile.transcriptionAPIKey,
                model: trimmedModel,
                language: resolvedProfile.languageHint
            )
        )
    }
}