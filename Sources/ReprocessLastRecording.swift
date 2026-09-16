import Foundation

/// Pure eligibility rules for the "Re-run Last Recording" action. Kept
/// dependency-free (like `LanguageProfiles`) so the busy-state gate,
/// the latest-Physical-Recording lookup, and the profile-exclusion
/// rule are deterministically testable without a live `AppState`.
enum ReprocessLastRecording {

    /// One eligible Physical Recording resolved for reprocessing: the
    /// history row that identifies it plus the on-disk WAV URL that
    /// was confirmed to exist at resolution time. Not `Equatable`
    /// because `PipelineHistoryItem` is not; tests compare the
    /// specific fields they care about (typically `item.id` and
    /// `audioURL`) directly instead.
    struct EligibleRecording {
        let item: PipelineHistoryItem
        let audioURL: URL
    }

    /// Concise, non-destructive feedback surfaced to the user when the
    /// action cannot proceed. None of these mutate history or start a
    /// Processing Attempt.
    enum Failure: Error, Equatable {
        case noPhysicalRecording
        case missingAudioFile(fileName: String)
        case noEligibleProfile

        var message: String {
            switch self {
            case .noPhysicalRecording:
                return "No saved recording to reprocess."
            case .missingAudioFile:
                return "The saved audio file could not be found."
            case .noEligibleProfile:
                return "No other Language Profile is available."
            }
        }
    }

    /// Whether a Re-run Last Recording shortcut trigger must be
    /// ignored outright — no lookup, no chooser, no feedback overlay —
    /// because recording, transcribing, a history Retry, or another
    /// reprocessing attempt is already in flight. Mirrors
    /// `LanguageProfiles.shouldRejectSwitchLanguageTrigger`'s "skip
    /// entirely, never queue" contract.
    static func shouldRejectTrigger(
        isRecording: Bool,
        isTranscribing: Bool,
        isHistoryRetryActive: Bool,
        isReprocessingActive: Bool
    ) -> Bool {
        isRecording || isTranscribing || isHistoryRetryActive || isReprocessingActive
    }

    /// The reverse direction of the mutual exclusion above: whether
    /// `AppState.retryTranscription(item:)` must reject a history
    /// Retry outright — no lookup, no state change — because the
    /// Re-run Last Recording chooser is open or a reprocessing `Task`
    /// is in flight. Kept as its own named, pure predicate (mirroring
    /// `shouldRejectTrigger`) so both directions of the mutual
    /// exclusion have an independently testable seam instead of an
    /// inline boolean at the call site.
    static func shouldRejectHistoryRetryTrigger(isReprocessingActive: Bool) -> Bool {
        isReprocessingActive
    }

    /// Resolve the latest Physical Recording eligible for
    /// reprocessing from retained history: the row with the latest
    /// `effectiveCaptureTime` that references a saved WAV (including
    /// one whose first transcription failed — `latestPhysicalRecording`
    /// does not filter by outcome), and confirm the WAV is still on
    /// disk. Never mutates `history`.
    static func resolveLatestEligibleRecording(
        history: [PipelineHistoryItem],
        audioStorageDirectory: URL,
        fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> Result<EligibleRecording, Failure> {
        guard let latest = PipelineHistoryItem.latestPhysicalRecording(in: history),
              let audioFileName = latest.audioFileName, !audioFileName.isEmpty else {
            return .failure(.noPhysicalRecording)
        }
        let audioURL = audioStorageDirectory.appendingPathComponent(audioFileName)
        guard fileExists(audioURL) else {
            return .failure(.missingAudioFile(fileName: audioFileName))
        }
        return .success(EligibleRecording(item: latest, audioURL: audioURL))
    }

    /// Profiles eligible to reprocess a Physical Recording with,
    /// preserving the catalog's configured order. The original
    /// profile is excluded only while it still exists in the
    /// catalog — a profile whose UUID was deleted (including a
    /// deleted-then-recreated same-language profile, which receives a
    /// brand-new UUID) is not excluded, so it remains eligible.
    /// Auto-detect and every specific language are always
    /// cross-eligible against each other; this function never filters
    /// by language code, only by UUID identity.
    static func eligibleProfiles(
        catalog: LanguageProfileCatalog,
        excludingOriginalProfileID: UUID?
    ) -> [LanguageProfile] {
        guard let excludingOriginalProfileID else { return catalog.profiles }
        return catalog.profiles.filter { $0.id != excludingOriginalProfileID }
    }

    /// Build the new linked `PipelineHistoryItem` for one reprocessing
    /// attempt. Shares `originalItem`'s Physical Recording identity
    /// and on-disk WAV (no audio copy) and reuses its intent, selected
    /// text, and full context snapshot verbatim — reprocessing never
    /// captures fresh context. `systemPrompt` and `customVocabulary`
    /// must be the values ACTUALLY used for this attempt (the chosen
    /// profile's resolved cleanup prompt and the vocabulary captured
    /// at reprocessing start), never `originalItem`'s stored values,
    /// which belong to a possibly different attempt/profile. Pure and
    /// side-effect-free: `originalItem` is never mutated, and the
    /// caller is responsible for persisting the returned item.
    static func makeLinkedHistoryItem(
        originalItem: PipelineHistoryItem,
        processingProfile: ResolvedLanguageProfile,
        rawTranscript: String,
        postProcessedTranscript: String,
        postProcessingPrompt: String,
        systemPrompt: String,
        processingStatus: String,
        customVocabulary: String,
        debugStatus: String = "Reprocessed",
        timestamp: Date = Date()
    ) -> PipelineHistoryItem {
        PipelineHistoryItem(
            intent: originalItem.intent,
            selectedText: originalItem.selectedText,
            capturedSelection: originalItem.capturedSelection,
            timestamp: timestamp,
            rawTranscript: rawTranscript,
            postProcessedTranscript: postProcessedTranscript,
            postProcessingPrompt: postProcessingPrompt,
            systemPrompt: systemPrompt,
            contextSummary: originalItem.contextSummary,
            contextSystemPrompt: originalItem.contextSystemPrompt,
            contextPrompt: originalItem.contextPrompt,
            contextScreenshotDataURL: originalItem.contextScreenshotDataURL,
            contextScreenshotStatus: originalItem.contextScreenshotStatus,
            postProcessingStatus: processingStatus,
            debugStatus: debugStatus,
            customVocabulary: customVocabulary,
            audioFileName: originalItem.audioFileName,
            contextAppName: originalItem.contextAppName,
            contextBundleIdentifier: originalItem.contextBundleIdentifier,
            contextWindowTitle: originalItem.contextWindowTitle,
            recordingID: originalItem.effectiveRecordingID,
            captureTime: originalItem.effectiveCaptureTime,
            originalProfileID: originalItem.originalProfileID,
            originalProfileName: originalItem.originalProfileName,
            originalInputLanguageCode: originalItem.originalInputLanguageCode,
            processingProfileID: processingProfile.profileID,
            processingProfileName: processingProfile.profileName,
            processingInputLanguageCode: processingProfile.inputLanguageCode
        )
    }

    /// Persist one linked history row through an injected append
    /// operation matching `PipelineHistoryStore.append(_:maxCount:)`'s
    /// exact signature (`(PipelineHistoryItem, Int) throws -> [String]`,
    /// returning the audio filenames whose last reference was dropped
    /// by trimming). Extracted so `AppState.recordReprocessedHistoryEntry`'s
    /// success/failure decision — which the "never paste an
    /// unretained result" guard below depends on — is deterministically
    /// testable with a throwing mock append closure, without a live
    /// CoreData-backed `PipelineHistoryStore`.
    static func persistLinkedHistoryItem(
        _ item: PipelineHistoryItem,
        maxCount: Int,
        append: (PipelineHistoryItem, Int) throws -> [String]
    ) -> Result<[String], Error> {
        Result { try append(item, maxCount) }
    }
}

/// Outcome `AppState.applySuccess` must produce for one completed
/// reprocessing attempt, decided purely from whether the linked
/// history row was actually persisted and whether there is a
/// non-empty result to paste. Extracted as a pure function so both
/// "never paste" guards — a failed history save, and nothing to paste
/// — are deterministically testable without a live `AppState`,
/// `PipelineHistoryStore`, or pasteboard. `AppState` switches on this
/// value directly, so its tests prove production's actual decision.
enum ReprocessSuccessOutcome: Equatable {
    /// The linked history row was NOT persisted. A result that was
    /// never actually retained must never be pasted; the caller shows
    /// a concise failure instead and never touches the clipboard.
    case historySaveFailed
    /// The linked history row was persisted, but the final transcript
    /// is empty — nothing to paste. The reprocessing lifecycle ends
    /// here with no further action.
    case nothingToPaste
    /// The linked history row was persisted and there is a non-empty
    /// result: the caller may write the clipboard and schedule the
    /// deferred, shortcut-released paste.
    case shouldPaste

    static func decide(historySaved: Bool, trimmedFinalTranscript: String) -> ReprocessSuccessOutcome {
        guard historySaved else { return .historySaveFailed }
        guard !trimmedFinalTranscript.isEmpty else { return .nothingToPaste }
        return .shouldPaste
    }
}

/// Pure lifecycle-phase model backing `AppState.isReprocessingLastRecordingActive`.
/// Mirrors the exact phases production drives
/// `AppState.reprocessLastRecordingPhase` through:
///
/// - `.idle`: no reprocessing attempt in flight.
/// - `.taskInFlight`: the coordinator's `Task` is transcribing,
///   processing, or has just appended the linked history row.
/// - `.pasteWindowPending`: history has already been appended and a
///   successful, non-empty result is queued to paste — deferred until
///   the shortcut that triggered reprocessing is released (see
///   `AppState.performAfterShortcutReleased`). This phase is the fix
///   for the reviewed defect: the busy guard must stay active through
///   this deferred window, not just through the task itself, or a
///   concurrent history Retry could overwrite the pasteboard before
///   the queued reprocessing paste fires.
///
/// `.idle` is reached again when: the task fails, the task succeeds
/// with nothing to paste, the task is cancelled before finishing, or
/// the pending paste window closes (fired or cancelled) — the pending
/// paste always eventually fires or is cancelled, so this phase can
/// never get stuck non-idle forever.
enum ReprocessLastRecordingPhase: Equatable {
    case idle
    case taskInFlight
    case pasteWindowPending

    /// True for every phase except `.idle`. The single predicate
    /// `AppState.isReprocessingLastRecordingActive` and
    /// `retryTranscription`/the Run Log Retry button read to decide
    /// whether History Retry must be rejected.
    var isBusy: Bool {
        self != .idle
    }
}

/// Non-activating chooser state for picking a Language Profile to
/// reprocess the latest Physical Recording with. Pure value type so
/// arrow/Return/Escape navigation is deterministically testable
/// without a real `NSPanel` or keyboard event.
struct ReprocessProfileChooserState: Equatable {
    /// Identifies the Physical Recording row the chooser was opened
    /// for, so a stale chooser interaction cannot be misapplied if
    /// history changes while the chooser is open.
    let recordingItemID: UUID
    /// Eligible profiles in configured order, captured when the
    /// chooser opened.
    let profiles: [LanguageProfile]
    fileprivate(set) var selectedIndex: Int

    fileprivate init(recordingItemID: UUID, profiles: [LanguageProfile], selectedIndex: Int) {
        self.recordingItemID = recordingItemID
        self.profiles = profiles
        self.selectedIndex = selectedIndex
    }

    var selectedProfile: LanguageProfile {
        profiles[selectedIndex]
    }
}

/// Key events the chooser reacts to. Every other keyboard input
/// (including configured global shortcuts) is suppressed while the
/// chooser is open — see `AppState.handleShortcutEvent`.
enum ReprocessChooserKey {
    case up
    case down
    case confirm
    case cancel
}

/// Outcome of applying a `ReprocessChooserKey` to a
/// `ReprocessProfileChooserState`.
enum ReprocessChooserOutcome: Equatable {
    case navigated(ReprocessProfileChooserState)
    case confirmed(LanguageProfile)
    case cancelled
}

enum ReprocessProfileChooser {
    /// Open the chooser for the supplied eligible profiles. Returns
    /// nil when there are no eligible profiles — the caller must
    /// surface `ReprocessLastRecording.Failure.noEligibleProfile`
    /// instead of opening an empty chooser.
    static func open(
        recordingItemID: UUID,
        eligibleProfiles: [LanguageProfile]
    ) -> ReprocessProfileChooserState? {
        guard !eligibleProfiles.isEmpty else { return nil }
        return ReprocessProfileChooserState(
            recordingItemID: recordingItemID,
            profiles: eligibleProfiles,
            selectedIndex: 0
        )
    }

    /// Apply one key event to the chooser state. Up/Down wrap at the
    /// ends of the configured-order list; Return confirms the
    /// currently highlighted profile; Escape cancels without mutating
    /// the Active Profile or starting any Processing Attempt.
    static func handle(
        _ key: ReprocessChooserKey,
        state: ReprocessProfileChooserState
    ) -> ReprocessChooserOutcome {
        switch key {
        case .up:
            var next = state
            next.selectedIndex = state.selectedIndex == 0
                ? state.profiles.count - 1
                : state.selectedIndex - 1
            return .navigated(next)
        case .down:
            var next = state
            next.selectedIndex = (state.selectedIndex + 1) % state.profiles.count
            return .navigated(next)
        case .confirm:
            return .confirmed(state.selectedProfile)
        case .cancel:
            return .cancelled
        }
    }
}

/// Testable orchestration for one "Re-run Last Recording" reprocessing
/// attempt. Every boundary — transcription, trailing-voice-command
/// parsing, the dictation/Edit-Mode processing pipeline, and the two
/// mutating MainActor side effects (history append, paste) — is
/// injected so the whole pipeline is exercised deterministically in
/// tests without a live provider, real audio, or the real Accessibility
/// / paste APIs.
///
/// Cancellation contract: `run(audioURL:)` must be launched inside a
/// cancellable `Task`. Cancellation is checked at every checkpoint via
/// `Task.checkCancellation()` / `Task.isCancelled`, INCLUDING
/// immediately inside the MainActor closure passed to
/// `Dependencies.runOnMainActor` — not only before the `await` that
/// performs the actor hop. A cancellation that arrives during that hop
/// (e.g. Escape pressed while the coordinator is suspended waiting to
/// resume on the main actor) must still be observed there, so it can
/// never race a history-store append or a paste through.
final class ReprocessLastRecordingCoordinator: @unchecked Sendable {

    struct SuccessPayload: Sendable {
        let rawTranscript: String
        let finalTranscript: String
        let processingStatus: String
        let postProcessingPrompt: String
    }

    struct FailurePayload: Sendable {
        let errorDescription: String
    }

    /// `applySuccess`, `applyFailure`, and `runOnMainActor`'s `body`
    /// parameter are `@Sendable` because they cross the MainActor hop
    /// — a real compiler-enforced boundary, not just documentation:
    /// `MainActor.run(body:)` requires its `body` argument to be
    /// `@Sendable`. `transcribe`/`parseTranscriptCommands`/`process`
    /// run before that hop and are invoked directly, so they carry no
    /// such requirement and may freely capture non-Sendable
    /// production types (e.g. `PostProcessingService`).
    struct Dependencies {
        /// Produce the raw transcript for the saved WAV. Production
        /// wires this to the resolved profile's saved-file-or-local
        /// `TranscriptionService` (never `RealtimeTranscriptionService`).
        var transcribe: (URL) async throws -> String
        /// Strip a trailing "press enter" voice-command marker the
        /// same way ordinary dictation does, so the pasted transcript
        /// stays clean. The coordinator never acts on the returned
        /// `shouldPressEnterAfterPaste` flag — reprocessing never
        /// synthesizes Return.
        var parseTranscriptCommands: (String) -> (transcript: String, shouldPressEnterAfterPaste: Bool)
        /// Run the existing dictation / Edit-Mode processing pipeline
        /// (voice macros, translation, preserve-exact-wording, LLM
        /// post-processing, or Edit Mode command-transform) exactly as
        /// production's transcript processing does.
        var process: (String) async -> (finalTranscript: String, statusMessage: String, prompt: String)
        /// MainActor mutating success path: append the linked history
        /// row (sharing the Physical Recording and WAV) and trigger
        /// paste. Invoked only when the coordinator's cancellation
        /// recheck inside the actor hop passes.
        var applySuccess: @Sendable (SuccessPayload) -> Void
        /// MainActor mutating failure path: append the failed linked
        /// history row. Never pastes. Invoked only when the
        /// coordinator's cancellation recheck inside the actor hop
        /// passes.
        var applyFailure: @Sendable (FailurePayload) -> Void
        /// Hop to the MainActor. Production passes a closure that
        /// calls `await MainActor.run(body:)`. Tests can inject a
        /// closure that pauses on a controllable gate so a test can
        /// deterministically cancel the enclosing `Task` while the
        /// coordinator is suspended mid-hop, exercising the exact
        /// race the cancellation recheck inside the closure guards
        /// against.
        var runOnMainActor: (@escaping @Sendable () -> Void) async -> Void
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func run(audioURL: URL) async {
        // Extract only the `@Sendable` boundary dependencies up front
        // so the closures built below capture just these two values
        // (plus locally-computed Sendable data), never the whole
        // `Dependencies` struct — which also holds the non-Sendable
        // `transcribe`/`process` closures that must never cross the
        // MainActor hop.
        let applySuccess = dependencies.applySuccess
        let applyFailure = dependencies.applyFailure
        do {
            try Task.checkCancellation()
            let rawTranscript = try await dependencies.transcribe(audioURL)
            let parsed = dependencies.parseTranscriptCommands(rawTranscript)
            try Task.checkCancellation()
            let result = await dependencies.process(parsed.transcript)
            try Task.checkCancellation()
            await dependencies.runOnMainActor {
                // Re-check cancellation INSIDE the MainActor closure.
                // A cancellation that arrived during the actor hop
                // above (e.g. Escape fired while this coordinator was
                // suspended waiting to resume on the main actor) must
                // still be caught here, so it can never race the
                // history append or paste below.
                guard !Task.isCancelled else { return }
                applySuccess(
                    SuccessPayload(
                        rawTranscript: parsed.transcript,
                        finalTranscript: result.finalTranscript,
                        processingStatus: result.statusMessage,
                        postProcessingPrompt: result.prompt
                    )
                )
            }
        } catch is CancellationError {
            return
        } catch {
            // Extract the description now so the MainActor closure
            // below captures a plain `String` instead of the `Error`
            // existential.
            let errorDescription = error.localizedDescription
            await dependencies.runOnMainActor {
                // Same cancellation recheck as the success path above.
                guard !Task.isCancelled else { return }
                applyFailure(FailurePayload(errorDescription: errorDescription))
            }
        }
    }
}
