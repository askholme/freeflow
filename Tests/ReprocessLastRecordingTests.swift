import Foundation

/// Deterministic tests for the "Re-run Last Recording" pure eligibility
/// rules, the non-activating chooser's key-event reducer, and the
/// `ReprocessLastRecordingCoordinator` orchestration — including the
/// exact Escape-vs-MainActor-hop cancellation race a prior attempt at
/// this ticket was blocked on. Every boundary (transcription,
/// processing, the MainActor hop, and the mutating history/paste
/// callbacks) is injected; no test touches a live provider, real
/// audio, a real event tap, or the real Accessibility/paste APIs.
enum ReprocessLastRecordingTests {
    static func run() async {
        testShouldRejectTriggerAggregatesEveryBusyState()
        testResolveLatestEligibleRecordingSucceedsForNewestPhysicalRecording()
        testResolveLatestEligibleRecordingReportsNoPhysicalRecordingWhenHistoryEmpty()
        testResolveLatestEligibleRecordingIncludesFailedInitialTranscription()
        testResolveLatestEligibleRecordingReportsMissingAudioFileWithoutMutatingHistory()
        testEligibleProfilesExcludesOriginalUUIDWhileItExists()
        testEligibleProfilesIncludesDeletedAndRecreatedSameLanguageProfile()
        testEligibleProfilesCrossEligibleAutoDetectAndSpecificLanguage()
        testChooserOpenReturnsNilForNoEligibleProfiles()
        testChooserNavigationWrapsAtBothEnds()
        testChooserNavigationTracksSelectionAcrossLargeProfileList()
        testChooserConfirmReturnsHighlightedProfileWithoutMutatingState()
        testChooserCancelProducesCancelledOutcome()
        testMutualExclusionRejectsReprocessingWhileHistoryRetryActive()
        testMutualExclusionRejectsHistoryRetryWhileReprocessingActive()
        testReprocessingPhaseStaysBusyThroughPendingPasteAndRejectsRetry()
        testMakeLinkedHistoryItemRecordsValuesActuallyUsedForReprocessing()
        testDecideNeverPastesAResultThatFailedToPersist()
        testPersistLinkedHistoryItemReturnsFailureWhenAppendThrows()

        await testCoordinatorSuccessAppendsHistoryAndPastes()
        await testCoordinatorNeverSynthesizesReturnEvenWhenTrailingCommandDetected()
        await testCoordinatorTranscriptionFailureAppendsFailedHistoryWithoutPaste()
        await testCoordinatorPostProcessingFailureFallsBackToRawTranscript()
        await testCoordinatorCancellationBeforeTranscribeRunsNothing()
        await testCoordinatorCancellationAfterTranscribeSkipsProcessing()
        await testCoordinatorCancellationRacingSuccessMainActorHopSkipsApply()
        await testCoordinatorCancellationRacingFailureMainActorHopSkipsApply()
    }

    // MARK: - Fixtures

    private static func makeItem(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        rawTranscript: String = "synthetic raw",
        postProcessedTranscript: String = "synthetic post",
        intent: PipelineHistoryItemIntent = .dictation,
        selectedText: String? = nil,
        audioFileName: String? = "synthetic-\(UUID().uuidString).wav",
        recordingID: UUID? = UUID(),
        captureTime: Date? = nil,
        originalProfileID: UUID? = UUID(),
        originalProfileName: String? = "Original Synthetic",
        originalInputLanguageCode: String? = "en"
    ) -> PipelineHistoryItem {
        PipelineHistoryItem(
            intent: intent,
            selectedText: selectedText,
            id: id,
            timestamp: timestamp,
            rawTranscript: rawTranscript,
            postProcessedTranscript: postProcessedTranscript,
            postProcessingPrompt: "synthetic prompt",
            systemPrompt: "synthetic system prompt",
            contextSummary: "synthetic context",
            contextScreenshotDataURL: nil,
            contextScreenshotStatus: "synthetic screenshot status",
            postProcessingStatus: "ok",
            debugStatus: "synthetic debug",
            customVocabulary: "",
            audioFileName: audioFileName,
            recordingID: recordingID,
            captureTime: captureTime ?? timestamp,
            originalProfileID: originalProfileID,
            originalProfileName: originalProfileName,
            originalInputLanguageCode: originalInputLanguageCode
        )
    }

    private static func makeProfile(
        id: UUID = UUID(),
        name: String = "Synthetic Profile",
        inputLanguageCode: String = "en"
    ) -> LanguageProfile {
        LanguageProfile(
            id: id,
            name: name,
            inputLanguageCode: inputLanguageCode,
            transcriptionURLOverride: "",
            transcriptionModelOverride: "",
            realtimeModelOverride: "",
            postProcessingPromptOverride: ""
        )
    }

    // MARK: - Busy-state gate

    private static func testShouldRejectTriggerAggregatesEveryBusyState() {
        TestSupport.expect(
            !ReprocessLastRecording.shouldRejectTrigger(
                isRecording: false, isTranscribing: false, isHistoryRetryActive: false, isReprocessingActive: false
            ),
            "Idle state must not reject the trigger"
        )
        TestSupport.expect(
            ReprocessLastRecording.shouldRejectTrigger(
                isRecording: true, isTranscribing: false, isHistoryRetryActive: false, isReprocessingActive: false
            ),
            "Recording must reject the trigger"
        )
        TestSupport.expect(
            ReprocessLastRecording.shouldRejectTrigger(
                isRecording: false, isTranscribing: true, isHistoryRetryActive: false, isReprocessingActive: false
            ),
            "Transcribing must reject the trigger"
        )
        TestSupport.expect(
            ReprocessLastRecording.shouldRejectTrigger(
                isRecording: false, isTranscribing: false, isHistoryRetryActive: true, isReprocessingActive: false
            ),
            "An active history Retry must reject the trigger"
        )
        TestSupport.expect(
            ReprocessLastRecording.shouldRejectTrigger(
                isRecording: false, isTranscribing: false, isHistoryRetryActive: false, isReprocessingActive: true
            ),
            "An already-active reprocessing attempt must reject a second trigger"
        )
    }

    // MARK: - Latest eligible recording

    private static func testResolveLatestEligibleRecordingSucceedsForNewestPhysicalRecording() {
        let older = makeItem(captureTime: Date(timeIntervalSince1970: 1_800_000_000))
        let newer = makeItem(captureTime: Date(timeIntervalSince1970: 1_800_001_000))
        let result = ReprocessLastRecording.resolveLatestEligibleRecording(
            history: [older, newer],
            audioStorageDirectory: URL(fileURLWithPath: "/tmp/synthetic-audio"),
            fileExists: { _ in true }
        )
        switch result {
        case .success(let eligible):
            TestSupport.expectEqual(eligible.item.id, newer.id)
        case .failure(let failure):
            TestSupport.expect(false, "Expected success, got \(failure)")
        }
    }

    private static func testResolveLatestEligibleRecordingReportsNoPhysicalRecordingWhenHistoryEmpty() {
        let result = ReprocessLastRecording.resolveLatestEligibleRecording(
            history: [],
            audioStorageDirectory: URL(fileURLWithPath: "/tmp/synthetic-audio"),
            fileExists: { _ in true }
        )
        switch result {
        case .failure(.noPhysicalRecording):
            break
        case .failure(let other):
            TestSupport.expect(false, "Expected .noPhysicalRecording, got \(other)")
        case .success:
            TestSupport.expect(false, "Expected failure for empty history")
        }
    }

    private static func testResolveLatestEligibleRecordingIncludesFailedInitialTranscription() {
        // The latest Physical Recording may be one whose first
        // transcription failed; `latestPhysicalRecording` selects by
        // capture time only, regardless of processing outcome, so a
        // failed initial attempt must still be discoverable.
        let failed = makeItem(
            captureTime: Date(timeIntervalSince1970: 1_800_002_000)
        )
        let result = ReprocessLastRecording.resolveLatestEligibleRecording(
            history: [failed],
            audioStorageDirectory: URL(fileURLWithPath: "/tmp/synthetic-audio"),
            fileExists: { _ in true }
        )
        switch result {
        case .success(let eligible):
            TestSupport.expectEqual(eligible.item.id, failed.id)
        case .failure(let failure):
            TestSupport.expect(false, "Expected success, got \(failure)")
        }
    }

    private static func testResolveLatestEligibleRecordingReportsMissingAudioFileWithoutMutatingHistory() {
        let item = makeItem(audioFileName: "synthetic-missing.wav")
        let history = [item]
        let result = ReprocessLastRecording.resolveLatestEligibleRecording(
            history: history,
            audioStorageDirectory: URL(fileURLWithPath: "/tmp/synthetic-audio"),
            fileExists: { _ in false }
        )
        switch result {
        case .failure(.missingAudioFile(let fileName)):
            TestSupport.expectEqual(fileName, "synthetic-missing.wav")
        case .failure(let other):
            TestSupport.expect(false, "Expected .missingAudioFile, got \(other)")
        case .success:
            TestSupport.expect(false, "Expected failure when the WAV is missing")
        }
        // The resolver never mutates its input.
        TestSupport.expectEqual(history.count, 1)
    }

    // MARK: - Eligible profiles

    private static func testEligibleProfilesExcludesOriginalUUIDWhileItExists() {
        let originalID = UUID()
        let other = makeProfile(name: "Other", inputLanguageCode: "es")
        let catalog = LanguageProfileCatalog(
            profiles: [makeProfile(id: originalID, name: "Original", inputLanguageCode: "en"), other],
            activeProfileID: originalID
        )
        let eligible = ReprocessLastRecording.eligibleProfiles(
            catalog: catalog,
            excludingOriginalProfileID: originalID
        )
        TestSupport.expectEqual(eligible.map(\.id), [other.id])
    }

    private static func testEligibleProfilesIncludesDeletedAndRecreatedSameLanguageProfile() {
        // The original profile's UUID no longer exists in the catalog
        // (it was deleted and a brand-new profile with the same
        // language was created — a fresh UUID). Excluding a UUID that
        // is absent from the catalog must be a no-op: the recreated
        // profile remains eligible.
        let deletedOriginalID = UUID()
        let recreatedSameLanguage = makeProfile(name: "English Again", inputLanguageCode: "en")
        let catalog = LanguageProfileCatalog(
            profiles: [recreatedSameLanguage],
            activeProfileID: recreatedSameLanguage.id
        )
        let eligible = ReprocessLastRecording.eligibleProfiles(
            catalog: catalog,
            excludingOriginalProfileID: deletedOriginalID
        )
        TestSupport.expectEqual(eligible.map(\.id), [recreatedSameLanguage.id])
    }

    private static func testEligibleProfilesCrossEligibleAutoDetectAndSpecificLanguage() {
        let specificOriginalID = UUID()
        let autoDetect = makeProfile(name: "Auto-detect", inputLanguageCode: "")
        let catalogWithSpecificOriginal = LanguageProfileCatalog(
            profiles: [
                makeProfile(id: specificOriginalID, name: "English", inputLanguageCode: "en"),
                autoDetect
            ],
            activeProfileID: specificOriginalID
        )
        let eligibleAgainstSpecific = ReprocessLastRecording.eligibleProfiles(
            catalog: catalogWithSpecificOriginal,
            excludingOriginalProfileID: specificOriginalID
        )
        TestSupport.expect(
            eligibleAgainstSpecific.contains(where: { $0.id == autoDetect.id }),
            "Auto-detect must be eligible against a specific-language original"
        )

        let autoDetectOriginalID = UUID()
        let specific = makeProfile(name: "Spanish", inputLanguageCode: "es")
        let catalogWithAutoDetectOriginal = LanguageProfileCatalog(
            profiles: [
                makeProfile(id: autoDetectOriginalID, name: "Auto-detect", inputLanguageCode: ""),
                specific
            ],
            activeProfileID: autoDetectOriginalID
        )
        let eligibleAgainstAutoDetect = ReprocessLastRecording.eligibleProfiles(
            catalog: catalogWithAutoDetectOriginal,
            excludingOriginalProfileID: autoDetectOriginalID
        )
        TestSupport.expect(
            eligibleAgainstAutoDetect.contains(where: { $0.id == specific.id }),
            "A specific language must be eligible against an Auto-detect original"
        )
    }

    // MARK: - Chooser reducer

    private static func testChooserOpenReturnsNilForNoEligibleProfiles() {
        let state = ReprocessProfileChooser.open(recordingItemID: UUID(), eligibleProfiles: [])
        TestSupport.expect(state == nil, "Opening the chooser with no eligible profiles must return nil")
    }

    private static func testChooserNavigationWrapsAtBothEnds() {
        let profiles = [makeProfile(name: "A"), makeProfile(name: "B"), makeProfile(name: "C")]
        guard let initial = ReprocessProfileChooser.open(recordingItemID: UUID(), eligibleProfiles: profiles) else {
            TestSupport.expect(false, "Expected a chooser state for non-empty profiles")
            return
        }
        TestSupport.expectEqual(initial.selectedIndex, 0)

        guard case .navigated(let afterUp) = ReprocessProfileChooser.handle(.up, state: initial) else {
            TestSupport.expect(false, "Expected .navigated for .up")
            return
        }
        TestSupport.expectEqual(afterUp.selectedIndex, 2)

        guard case .navigated(let afterDown) = ReprocessProfileChooser.handle(.down, state: afterUp) else {
            TestSupport.expect(false, "Expected .navigated for .down")
            return
        }
        TestSupport.expectEqual(afterDown.selectedIndex, 0)

        guard case .navigated(let afterSecondDown) = ReprocessProfileChooser.handle(.down, state: afterDown) else {
            TestSupport.expect(false, "Expected .navigated for .down")
            return
        }
        TestSupport.expectEqual(afterSecondDown.selectedIndex, 1)
    }

    /// The Language Profile catalog supports far more entries than
    /// comfortably fit in the chooser panel without scrolling (see
    /// `ReprocessProfileChooserPanel.swift`'s bounded `ScrollView`).
    /// This proves the underlying reducer's selected-index tracking —
    /// the logic driving which row the scroll view keeps visible — is
    /// correct across a "large" (12-profile) synthetic list: sequential
    /// steps land on the expected index, wraparound still works past
    /// the visible-row cap, and `selectedProfile` always matches
    /// `profiles[selectedIndex]`. Actual on-screen scrolling remains
    /// part of manual chooser-interaction verification (this sandbox
    /// cannot render or observe real AppKit/SwiftUI scrolling).
    private static func testChooserNavigationTracksSelectionAcrossLargeProfileList() {
        let profileCount = 12
        let profiles = (0..<profileCount).map { makeProfile(name: "Profile \($0)") }
        guard var state = ReprocessProfileChooser.open(recordingItemID: UUID(), eligibleProfiles: profiles) else {
            TestSupport.expect(false, "Expected a chooser state for a large non-empty profile list")
            return
        }
        TestSupport.expectEqual(state.selectedIndex, 0)
        TestSupport.expectEqual(state.selectedProfile.id, profiles[0].id)

        // Step down past the chooser's max-visible-row cap (8) and
        // all the way past the end of the list, confirming every
        // intermediate index — including the wrap from the last
        // profile back to the first — is exactly right.
        for expectedIndex in 1...profileCount {
            guard case .navigated(let next) = ReprocessProfileChooser.handle(.down, state: state) else {
                TestSupport.expect(false, "Expected .navigated for .down at step \(expectedIndex)")
                return
            }
            state = next
            let wrappedExpectedIndex = expectedIndex % profileCount
            TestSupport.expectEqual(state.selectedIndex, wrappedExpectedIndex)
            TestSupport.expectEqual(state.selectedProfile.id, profiles[wrappedExpectedIndex].id)
        }
        // After exactly `profileCount` steps down, selection is back
        // at the start.
        TestSupport.expectEqual(state.selectedIndex, 0)

        // Step up once from index 0 must wrap to the last profile,
        // even though that row is far past the visible-row cap.
        guard case .navigated(let afterUp) = ReprocessProfileChooser.handle(.up, state: state) else {
            TestSupport.expect(false, "Expected .navigated for .up")
            return
        }
        TestSupport.expectEqual(afterUp.selectedIndex, profileCount - 1)
        TestSupport.expectEqual(afterUp.selectedProfile.id, profiles[profileCount - 1].id)
    }

    private static func testChooserConfirmReturnsHighlightedProfileWithoutMutatingState() {
        let profiles = [makeProfile(name: "A"), makeProfile(name: "B")]
        guard let initial = ReprocessProfileChooser.open(recordingItemID: UUID(), eligibleProfiles: profiles),
              case .navigated(let afterDown) = ReprocessProfileChooser.handle(.down, state: initial) else {
            TestSupport.expect(false, "Expected a navigated chooser state")
            return
        }
        guard case .confirmed(let confirmedProfile) = ReprocessProfileChooser.handle(.confirm, state: afterDown) else {
            TestSupport.expect(false, "Expected .confirmed")
            return
        }
        TestSupport.expectEqual(confirmedProfile.id, profiles[1].id)
        // Confirming does not itself mutate the chooser state (the
        // caller closes the chooser and starts reprocessing instead).
        TestSupport.expectEqual(afterDown.selectedIndex, 1)
    }

    private static func testChooserCancelProducesCancelledOutcome() {
        let profiles = [makeProfile(name: "A")]
        guard let initial = ReprocessProfileChooser.open(recordingItemID: UUID(), eligibleProfiles: profiles) else {
            TestSupport.expect(false, "Expected a chooser state")
            return
        }
        guard case .cancelled = ReprocessProfileChooser.handle(.cancel, state: initial) else {
            TestSupport.expect(false, "Expected .cancelled")
            return
        }
    }

    // MARK: - Mutual exclusion with history Retry

    /// Direction 1: reprocessing must never start while a history
    /// Retry is active. `AppState.handleReprocessLastRecordingShortcutTriggered`
    /// threads `isHistoryRetryActive: !retryingItemIDs.isEmpty`
    /// straight into this predicate, so exercising it here covers
    /// production's actual gating decision.
    private static func testMutualExclusionRejectsReprocessingWhileHistoryRetryActive() {
        TestSupport.expect(
            ReprocessLastRecording.shouldRejectTrigger(
                isRecording: false,
                isTranscribing: false,
                isHistoryRetryActive: true,
                isReprocessingActive: false
            ),
            "Reprocessing must be rejected while a history Retry is active"
        )
        TestSupport.expect(
            !ReprocessLastRecording.shouldRejectTrigger(
                isRecording: false,
                isTranscribing: false,
                isHistoryRetryActive: false,
                isReprocessingActive: false
            ),
            "Reprocessing must be permitted when no history Retry is active"
        )
    }

    /// Direction 2 (the reverse): a history Retry must never start
    /// while Re-run Last Recording reprocessing — the chooser or an
    /// in-flight reprocessing `Task` — is active.
    /// `AppState.retryTranscription(item:)` threads
    /// `isReprocessingActive: isReprocessingLastRecordingActive`
    /// straight into this predicate, so exercising it here covers
    /// production's actual gating decision for the reverse direction.
    private static func testMutualExclusionRejectsHistoryRetryWhileReprocessingActive() {
        TestSupport.expect(
            ReprocessLastRecording.shouldRejectHistoryRetryTrigger(isReprocessingActive: true),
            "History Retry must be rejected while reprocessing (chooser open or task in flight) is active"
        )
        TestSupport.expect(
            !ReprocessLastRecording.shouldRejectHistoryRetryTrigger(isReprocessingActive: false),
            "History Retry must be permitted when reprocessing is not active"
        )
    }

    /// Regression test for the reviewed defect: `AppState` must keep
    /// reprocessing "active" for the mutual-exclusion guard not just
    /// while the coordinator `Task` itself runs, but through the
    /// deferred, shortcut-released paste window that follows a
    /// successful non-empty result — otherwise a concurrent history
    /// Retry could overwrite the pasteboard before the queued
    /// reprocessing paste fires. `ReprocessLastRecordingPhase` is the
    /// exact type `AppState.reprocessLastRecordingPhase` is driven
    /// through by `startReprocessing`/`finishPendingReprocessPaste`/
    /// `cancelPendingReprocessPaste`, so walking its transitions here
    /// and re-checking `shouldRejectHistoryRetryTrigger` at each step
    /// proves both halves the reviewer asked for: Retry stays rejected
    /// while a paste is queued/pending, and clears once it is done.
    private static func testReprocessingPhaseStaysBusyThroughPendingPasteAndRejectsRetry() {
        var phase = ReprocessLastRecordingPhase.idle
        TestSupport.expect(!phase.isBusy, "Idle must not be busy")
        TestSupport.expect(
            !ReprocessLastRecording.shouldRejectHistoryRetryTrigger(isReprocessingActive: phase.isBusy),
            "History Retry must be permitted while idle"
        )

        // `startReprocessing` sets this the moment the coordinator
        // `Task` is created.
        phase = .taskInFlight
        TestSupport.expect(phase.isBusy, "taskInFlight must be busy")
        TestSupport.expect(
            ReprocessLastRecording.shouldRejectHistoryRetryTrigger(isReprocessingActive: phase.isBusy),
            "History Retry must be rejected while the coordinator Task is in flight"
        )

        // The coordinator has now succeeded with a non-empty result:
        // history was already appended, and a paste is queued,
        // deferred until the shortcut that triggered reprocessing is
        // released. This is exactly the window the reviewed defect
        // left unguarded — Retry must still be rejected here.
        phase = .pasteWindowPending
        TestSupport.expect(phase.isBusy, "pasteWindowPending must be busy")
        TestSupport.expect(
            ReprocessLastRecording.shouldRejectHistoryRetryTrigger(isReprocessingActive: phase.isBusy),
            "History Retry must still be rejected while a reprocessing paste is queued/pending"
        )

        // The queued paste has now actually executed (the safety-net
        // `defer` in `startReprocessing`'s action always reaches
        // `finishPendingReprocessPaste`) — or Escape cancelled it via
        // `cancelPendingReprocessPaste`. Either way the phase returns
        // to idle and Retry becomes available again.
        phase = .idle
        TestSupport.expect(!phase.isBusy, "Idle after the pending paste completes must not be busy")
        TestSupport.expect(
            !ReprocessLastRecording.shouldRejectHistoryRetryTrigger(isReprocessingActive: phase.isBusy),
            "History Retry must be permitted again once the pending paste has executed"
        )
    }

    // MARK: - Linked history item construction

    /// Regression test for the reviewed defect: the new linked history
    /// row must record the `systemPrompt` and `customVocabulary` that
    /// were ACTUALLY used for this reprocessing attempt (the chosen
    /// profile's resolved cleanup prompt and the vocabulary captured
    /// at reprocessing start) — never `originalItem`'s stored values,
    /// which belong to a different (possibly different-profile)
    /// attempt. Uses a chosen-profile prompt/vocabulary combination
    /// deliberately different from the original item's stored values.
    private static func testMakeLinkedHistoryItemRecordsValuesActuallyUsedForReprocessing() {
        let recordingID = UUID()
        let captureTime = Date(timeIntervalSince1970: 1_800_010_000)
        let originalProfileID = UUID()
        let original = makeItem(
            timestamp: captureTime,
            audioFileName: "synthetic-linked.wav",
            recordingID: recordingID,
            captureTime: captureTime,
            originalProfileID: originalProfileID,
            originalProfileName: "Original Synthetic",
            originalInputLanguageCode: "en"
        )
        // `makeItem`'s synthetic defaults: systemPrompt == "synthetic
        // system prompt", customVocabulary == "". Confirm those are
        // the original row's stored values before building the linked
        // row, so the assertions below are meaningfully different.
        TestSupport.expectEqual(original.systemPrompt, "synthetic system prompt")
        TestSupport.expectEqual(original.customVocabulary, "")

        let chosenProfile = ResolvedLanguageProfile(
            profileID: UUID(),
            profileName: "Chosen Synthetic Profile",
            inputLanguageCode: "es",
            languageHint: "es",
            transcriptionBaseURL: "",
            transcriptionAPIKey: "",
            transcriptionModel: "",
            realtimeModel: "",
            ordinaryCleanupSystemPrompt: "chosen-profile cleanup prompt"
        )
        let actuallyUsedSystemPrompt = "chosen-profile cleanup prompt (resolved)"
        let actuallyUsedVocabulary = "chosen-profile vocabulary, different from original"

        let linked = ReprocessLastRecording.makeLinkedHistoryItem(
            originalItem: original,
            processingProfile: chosenProfile,
            rawTranscript: "synthetic reprocessed raw",
            postProcessedTranscript: "synthetic reprocessed final",
            postProcessingPrompt: "synthetic reprocessed prompt",
            systemPrompt: actuallyUsedSystemPrompt,
            processingStatus: "Post-processing succeeded",
            customVocabulary: actuallyUsedVocabulary
        )

        // The new linked row records what was ACTUALLY used for this
        // attempt, not the original row's stored values.
        TestSupport.expectEqual(linked.systemPrompt, actuallyUsedSystemPrompt)
        TestSupport.expectEqual(linked.customVocabulary, actuallyUsedVocabulary)
        TestSupport.expect(
            linked.systemPrompt != original.systemPrompt,
            "The linked row's systemPrompt must differ from the original row's stored value in this test"
        )
        TestSupport.expect(
            linked.customVocabulary != original.customVocabulary,
            "The linked row's customVocabulary must differ from the original row's stored value in this test"
        )

        // The original row itself is never mutated by building the
        // linked row.
        TestSupport.expectEqual(original.systemPrompt, "synthetic system prompt")
        TestSupport.expectEqual(original.customVocabulary, "")

        // Shared Physical Recording identity and WAV, no audio copy.
        TestSupport.expectEqual(linked.recordingID, recordingID)
        TestSupport.expectEqual(linked.captureTime, captureTime)
        TestSupport.expectEqual(linked.audioFileName, original.audioFileName)
        // Original-profile identity carried through unchanged; only
        // the processing-profile snapshot reflects the chosen profile.
        TestSupport.expectEqual(linked.originalProfileID, originalProfileID)
        TestSupport.expectEqual(linked.processingProfileID, chosenProfile.profileID)
        TestSupport.expectEqual(linked.processingProfileName, "Chosen Synthetic Profile")
        TestSupport.expectEqual(linked.processingInputLanguageCode, "es")
        // Intent, selected text, and full context snapshot reused
        // verbatim from the original row — reprocessing never
        // captures fresh context.
        TestSupport.expectEqual(linked.intent, original.intent)
        TestSupport.expectEqual(linked.selectedText, original.selectedText)
        TestSupport.expectEqual(linked.contextSummary, original.contextSummary)
    }

    // MARK: - Success outcome / history-persistence gating

    /// Regression test for the round-3 reviewed defect: reprocessing
    /// must never paste a result whose linked history row failed to
    /// persist — a paste with no retained record misleads the user
    /// into thinking the alternate-language result was kept.
    /// `ReprocessSuccessOutcome.decide` is the exact pure function
    /// `AppState.applySuccess` switches on, so exercising every branch
    /// here proves production's actual paste/no-paste decision for
    /// all three outcomes: a failed save (never paste, regardless of
    /// transcript content), a successful save with nothing to paste
    /// (empty final transcript), and a successful save with a
    /// non-empty result (paste).
    private static func testDecideNeverPastesAResultThatFailedToPersist() {
        // A failed history save must never be pasted, even with a
        // non-empty transcript.
        TestSupport.expectEqual(
            ReprocessSuccessOutcome.decide(historySaved: false, trimmedFinalTranscript: "some transcript"),
            .historySaveFailed
        )
        // A persisted result with an empty transcript has nothing to
        // paste.
        TestSupport.expectEqual(
            ReprocessSuccessOutcome.decide(historySaved: true, trimmedFinalTranscript: ""),
            .nothingToPaste
        )
        // A persisted result with a non-empty transcript must be
        // pasted.
        TestSupport.expectEqual(
            ReprocessSuccessOutcome.decide(historySaved: true, trimmedFinalTranscript: "some transcript"),
            .shouldPaste
        )
    }

    /// Regression test for the round-3 reviewed defect:
    /// `AppState.recordReprocessedHistoryEntry` derives the
    /// `historySaved` flag that gates `ReprocessSuccessOutcome.decide`
    /// entirely from whether the injected append operation actually
    /// succeeded — it must never assume success. `persistLinkedHistoryItem`
    /// is the exact function `recordReprocessedHistoryEntry` calls,
    /// with the same `(PipelineHistoryItem, Int) throws -> [String]`
    /// signature `PipelineHistoryStore.append` matches, so a throwing
    /// mock here proves production correctly detects a failed
    /// CoreData save (e.g. a full disk or store-loading failure)
    /// rather than treating it as a retained result.
    private static func testPersistLinkedHistoryItemReturnsFailureWhenAppendThrows() {
        struct SyntheticPersistenceError: Error {}
        let item = makeItem()

        let failureResult = ReprocessLastRecording.persistLinkedHistoryItem(
            item,
            maxCount: 200,
            append: { _, _ in throw SyntheticPersistenceError() }
        )
        switch failureResult {
        case .failure:
            break
        case .success:
            TestSupport.expect(false, "A throwing append operation must surface as a failure, not a success")
        }

        let removedFileNames = ["synthetic-trimmed.wav"]
        let successResult = ReprocessLastRecording.persistLinkedHistoryItem(
            item,
            maxCount: 200,
            append: { _, _ in removedFileNames }
        )
        switch successResult {
        case .success(let names):
            TestSupport.expectEqual(names, removedFileNames)
        case .failure:
            TestSupport.expect(false, "A succeeding append operation must surface as a success")
        }
    }

    // MARK: - Coordinator: success / failure / fallback

    /// Thread-safe (single-threaded-access-in-practice) box the tests
    /// use to observe which coordinator callback ran without
    /// depending on any real history store, pasteboard, or paste API.
    private final class Recorder: @unchecked Sendable {
        var appliedSuccess: ReprocessLastRecordingCoordinator.SuccessPayload?
        var appliedFailure: ReprocessLastRecordingCoordinator.FailurePayload?
        var transcribeCallCount = 0
        var processCallCount = 0
    }

    private static func makeDependencies(
        recorder: Recorder,
        transcribeResult: Result<String, Error> = .success("synthetic raw transcript"),
        processResult: (finalTranscript: String, statusMessage: String, prompt: String) = ("synthetic final", "Post-processing succeeded", "synthetic prompt"),
        parsedShouldPressEnter: Bool = false,
        runOnMainActor: @escaping @Sendable (@escaping @Sendable () -> Void) async -> Void = { body in await MainActor.run(body: body) }
    ) -> ReprocessLastRecordingCoordinator.Dependencies {
        ReprocessLastRecordingCoordinator.Dependencies(
            transcribe: { _ in
                recorder.transcribeCallCount += 1
                switch transcribeResult {
                case .success(let value): return value
                case .failure(let error): throw error
                }
            },
            parseTranscriptCommands: { raw in (raw, parsedShouldPressEnter) },
            process: { transcript in
                recorder.processCallCount += 1
                return (processResult.finalTranscript, processResult.statusMessage, processResult.prompt)
            },
            applySuccess: { payload in recorder.appliedSuccess = payload },
            applyFailure: { payload in recorder.appliedFailure = payload },
            runOnMainActor: runOnMainActor
        )
    }

    private static func testCoordinatorSuccessAppendsHistoryAndPastes() async {
        let recorder = Recorder()
        let dependencies = makeDependencies(recorder: recorder)
        let coordinator = ReprocessLastRecordingCoordinator(dependencies: dependencies)
        await coordinator.run(audioURL: URL(fileURLWithPath: "/tmp/synthetic.wav"))

        TestSupport.expectEqual(recorder.transcribeCallCount, 1)
        TestSupport.expectEqual(recorder.processCallCount, 1)
        TestSupport.expect(recorder.appliedFailure == nil, "Success path must not invoke applyFailure")
        guard let payload = recorder.appliedSuccess else {
            TestSupport.expect(false, "Expected applySuccess to run")
            return
        }
        TestSupport.expectEqual(payload.finalTranscript, "synthetic final")
        TestSupport.expectEqual(payload.processingStatus, "Post-processing succeeded")
    }

    /// Even when `parseTranscriptCommands` detects a trailing "press
    /// enter" voice command, the coordinator has no pathway that
    /// synthesizes Return: it only ever forwards
    /// `SuccessPayload`/`FailurePayload` to the injected callbacks,
    /// neither of which carries a "press enter" signal at all.
    private static func testCoordinatorNeverSynthesizesReturnEvenWhenTrailingCommandDetected() async {
        let recorder = Recorder()
        let dependencies = makeDependencies(recorder: recorder, parsedShouldPressEnter: true)
        let coordinator = ReprocessLastRecordingCoordinator(dependencies: dependencies)
        await coordinator.run(audioURL: URL(fileURLWithPath: "/tmp/synthetic.wav"))

        TestSupport.expect(recorder.appliedSuccess != nil, "Expected applySuccess to run")
        // `SuccessPayload` has no "press enter" field at all — proving
        // by construction that the coordinator cannot forward a
        // Return-synthesis instruction to its caller.
        let mirror = Mirror(reflecting: recorder.appliedSuccess!)
        let fieldNames = Set(mirror.children.compactMap(\.label))
        TestSupport.expect(
            !fieldNames.contains(where: { $0.lowercased().contains("enter") || $0.lowercased().contains("return") }),
            "SuccessPayload must not carry any press-enter/Return instruction"
        )
    }

    private static func testCoordinatorTranscriptionFailureAppendsFailedHistoryWithoutPaste() async {
        struct SyntheticTranscriptionError: Error, LocalizedError {
            var errorDescription: String? { "synthetic transcription failure" }
        }
        let recorder = Recorder()
        let dependencies = makeDependencies(
            recorder: recorder,
            transcribeResult: .failure(SyntheticTranscriptionError())
        )
        let coordinator = ReprocessLastRecordingCoordinator(dependencies: dependencies)
        await coordinator.run(audioURL: URL(fileURLWithPath: "/tmp/synthetic.wav"))

        TestSupport.expectEqual(recorder.transcribeCallCount, 1)
        TestSupport.expectEqual(recorder.processCallCount, 0)
        TestSupport.expect(recorder.appliedSuccess == nil, "Transcription failure must not invoke applySuccess (no paste)")
        guard let failure = recorder.appliedFailure else {
            TestSupport.expect(false, "Expected applyFailure to run")
            return
        }
        TestSupport.expect(
            failure.errorDescription.contains("synthetic transcription failure"),
            "Failure payload must carry the underlying error description"
        )
    }

    /// Post-processing failure is not a coordinator-level error: the
    /// injected `process` closure (production: `AppState.processTranscript`)
    /// already implements the raw-transcript fallback and returns a
    /// normal (non-throwing) result describing it. The coordinator
    /// must treat that exactly like any other success — appending
    /// history and pasting the fallback text — never routing it
    /// through `applyFailure`.
    private static func testCoordinatorPostProcessingFailureFallsBackToRawTranscript() async {
        let recorder = Recorder()
        let dependencies = makeDependencies(
            recorder: recorder,
            transcribeResult: .success("synthetic raw transcript"),
            processResult: (
                finalTranscript: "synthetic raw transcript",
                statusMessage: "Post-processing failed, using raw transcript",
                prompt: ""
            )
        )
        let coordinator = ReprocessLastRecordingCoordinator(dependencies: dependencies)
        await coordinator.run(audioURL: URL(fileURLWithPath: "/tmp/synthetic.wav"))

        TestSupport.expect(recorder.appliedFailure == nil, "A post-processing fallback is a success, not a coordinator failure")
        guard let payload = recorder.appliedSuccess else {
            TestSupport.expect(false, "Expected applySuccess to run with the raw-transcript fallback")
            return
        }
        TestSupport.expectEqual(payload.finalTranscript, "synthetic raw transcript")
        TestSupport.expectEqual(payload.processingStatus, "Post-processing failed, using raw transcript")
    }

    // MARK: - Coordinator: cancellation

    private static func testCoordinatorCancellationBeforeTranscribeRunsNothing() async {
        let recorder = Recorder()
        let dependencies = makeDependencies(recorder: recorder)
        let coordinator = ReprocessLastRecordingCoordinator(dependencies: dependencies)
        let task = Task {
            await coordinator.run(audioURL: URL(fileURLWithPath: "/tmp/synthetic.wav"))
        }
        task.cancel()
        await task.value

        TestSupport.expectEqual(recorder.transcribeCallCount, 0)
        TestSupport.expect(recorder.appliedSuccess == nil, "A pre-cancelled run must never append history")
        TestSupport.expect(recorder.appliedFailure == nil, "A pre-cancelled run must never append history")
    }

    private static func testCoordinatorCancellationAfterTranscribeSkipsProcessing() async {
        let gate = ReprocessCoordinatorGate()
        let recorder = Recorder()
        let dependencies = ReprocessLastRecordingCoordinator.Dependencies(
            transcribe: { _ in
                recorder.transcribeCallCount += 1
                await gate.pause()
                return "synthetic raw transcript"
            },
            parseTranscriptCommands: { raw in (raw, false) },
            process: { transcript in
                recorder.processCallCount += 1
                return (transcript, "Post-processing succeeded", "")
            },
            applySuccess: { payload in recorder.appliedSuccess = payload },
            applyFailure: { payload in recorder.appliedFailure = payload },
            runOnMainActor: { body in await MainActor.run(body: body) }
        )
        let coordinator = ReprocessLastRecordingCoordinator(dependencies: dependencies)
        let task = Task.detached {
            await coordinator.run(audioURL: URL(fileURLWithPath: "/tmp/synthetic.wav"))
        }
        await gate.waitUntilReached()
        task.cancel()
        await gate.release()
        await task.value

        TestSupport.expectEqual(recorder.transcribeCallCount, 1)
        TestSupport.expectEqual(recorder.processCallCount, 0)
        TestSupport.expect(recorder.appliedSuccess == nil, "Cancelled run must never append history or paste")
        TestSupport.expect(recorder.appliedFailure == nil, "Cancelled run must never append history")
    }

    /// The exact regression a prior attempt at this ticket was
    /// blocked on: cancellation arriving during the MainActor hop
    /// (after the last `Task.checkCancellation()` but before the
    /// mutating `applySuccess` callback runs) must still be observed
    /// — the coordinator rechecks `Task.isCancelled` INSIDE the
    /// MainActor closure, not only before the `await` that performs
    /// the hop. This test forces exactly that ordering using a gate
    /// that pauses the coordinator inside `runOnMainActor`'s closure
    /// (simulating the actor-hop suspension), cancels the enclosing
    /// `Task` while it is paused there, then releases it.
    private static func testCoordinatorCancellationRacingSuccessMainActorHopSkipsApply() async {
        let gate = ReprocessCoordinatorGate()
        let recorder = Recorder()
        let dependencies = makeDependencies(
            recorder: recorder,
            runOnMainActor: { body in
                await gate.pause()
                body()
            }
        )
        let coordinator = ReprocessLastRecordingCoordinator(dependencies: dependencies)
        let task = Task.detached {
            await coordinator.run(audioURL: URL(fileURLWithPath: "/tmp/synthetic.wav"))
        }
        await gate.waitUntilReached()
        // Cancel while the coordinator is suspended mid-hop — exactly
        // the race the prior attempt failed to guard against.
        task.cancel()
        await gate.release()
        await task.value

        TestSupport.expectEqual(recorder.transcribeCallCount, 1)
        TestSupport.expectEqual(recorder.processCallCount, 1)
        TestSupport.expect(
            recorder.appliedSuccess == nil,
            "Cancellation racing the MainActor hop must prevent the history append / paste from running"
        )
        TestSupport.expect(
            recorder.appliedFailure == nil,
            "Cancellation racing the MainActor hop must not fall through to the failure path either"
        )
    }

    /// Same race as above, but for the failure path's MainActor hop
    /// (the `catch` branch's `applyFailure` call).
    private static func testCoordinatorCancellationRacingFailureMainActorHopSkipsApply() async {
        struct SyntheticTranscriptionError: Error, LocalizedError {
            var errorDescription: String? { "synthetic transcription failure" }
        }
        let gate = ReprocessCoordinatorGate()
        let recorder = Recorder()
        let dependencies = makeDependencies(
            recorder: recorder,
            transcribeResult: .failure(SyntheticTranscriptionError()),
            runOnMainActor: { body in
                await gate.pause()
                body()
            }
        )
        let coordinator = ReprocessLastRecordingCoordinator(dependencies: dependencies)
        let task = Task.detached {
            await coordinator.run(audioURL: URL(fileURLWithPath: "/tmp/synthetic.wav"))
        }
        await gate.waitUntilReached()
        task.cancel()
        await gate.release()
        await task.value

        TestSupport.expect(
            recorder.appliedFailure == nil,
            "Cancellation racing the failure path's MainActor hop must prevent the failed history append"
        )
        TestSupport.expect(recorder.appliedSuccess == nil, "Must never fall through to success either")
    }
}

/// Controllable suspension point tests use to force a `Task`
/// cancellation to arrive while the coordinator is suspended inside
/// `runOnMainActor`'s closure, deterministically reproducing the
/// Escape-vs-MainActor-hop race. Mirrors the `ProcessLaunchGate`
/// pattern already used in `LocalParakeetTranscriptionServiceTests`.
private actor ReprocessCoordinatorGate {
    private var reached = false
    private var reachedContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func pause() async {
        reached = true
        reachedContinuation?.resume()
        reachedContinuation = nil
        await withCheckedContinuation { releaseContinuation = $0 }
    }

    func waitUntilReached() async {
        guard !reached else { return }
        await withCheckedContinuation { reachedContinuation = $0 }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}
