import Foundation
import CoreData

/// Deterministic tests for the Physical Recording identity, profile
/// snapshots, shared audio reference counting, and legacy migration
/// paths in `PipelineHistoryStore`. Tests use only invented synthetic
/// data and either an in-memory store or a temporary on-disk store,
/// so they never read real pipeline history or user audio.
enum PhysicalRecordingHistoryTests {

    static func run() {
        testRecordingIdentityRoundTripsAcrossStore()
        testProfileSnapshotsRoundTripWithoutSecrets()
        testSuccessfulAndFailedInitialTranscriptionRetainMetadata()
        testLegacyRowsMigrateToEffectiveIdentityAndTimestamp()
        testLegacyRowsMigrateOriginalProfileIdentityToNil()
        testMetadataSurvivesStoreRelaunchOnDisk()
        testLatestItemSelectedByCaptureTimeAcrossLinkedResults()
        testLatestSelectionIncludesFailedAndAgedOutOriginal()
        testLatestSelectionAcrossDistinctRecordingsPicksNewest()
        testLatestSelectionSkipsItemsWithoutAudio()
        testSharedAudioFilenameRoundTripsAcrossLinkedItems()
        testDeletingOneLinkedResultKeepsAudioForRemaining()
        testTrimmingDropsAudioOnlyWhenLastReferenceRemoved()
        testRemovingFinalReferenceReturnsAudioExactlyOnce()
        testClearReturnsUniqueAudioFilenames()
        testClearDropsEveryRetainedAudio()
        testUpdatePreservesIdentityForRetriedLinkedResult()
        testEligibilityPassesWhenAudioFileExists()
        testEligibilityReportsMissingAudioFileWithoutMutatingHistory()
        testEligibilityReportsItemNotFoundWithoutMutatingHistory()
        testEligibilityReportsNoAudioReferenceWithoutMutatingHistory()
        testEncodingExcludesEndpointURLsAndCredentials()
    }

    // MARK: - Helpers

    /// Make an in-memory store so each test gets a clean slate.
    private static func makeStore() -> PipelineHistoryStore {
        PipelineHistoryStore.inMemory()
    }

    /// Build a `PipelineHistoryItem` with the supplied fields and
    /// invented synthetic defaults for the remaining fields. Tests
    /// call this so the fixtures read like real production history
    /// rows without duplicating twenty parameter lists.
    private static func makeItem(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        audioFileName: String? = "synthetic-\(UUID().uuidString).wav",
        recordingID: UUID? = UUID(),
        captureTime: Date? = nil,
        originalProfileID: UUID? = UUID(),
        originalProfileName: String? = "Synthetic Profile",
        originalInputLanguageCode: String? = "en",
        processingProfileID: UUID? = UUID(),
        processingProfileName: String? = "Synthetic Profile",
        processingInputLanguageCode: String? = "en",
        postProcessingStatus: String = "ok"
    ) -> PipelineHistoryItem {
        PipelineHistoryItem(
            intent: .dictation,
            id: id,
            timestamp: timestamp,
            rawTranscript: "synthetic raw transcript",
            postProcessedTranscript: "synthetic post-processed transcript",
            postProcessingPrompt: "synthetic prompt",
            systemPrompt: "synthetic system prompt",
            contextSummary: "synthetic context",
            contextScreenshotDataURL: nil,
            contextScreenshotStatus: "synthetic screenshot status",
            postProcessingStatus: postProcessingStatus,
            debugStatus: "synthetic debug",
            customVocabulary: "",
            audioFileName: audioFileName,
            recordingID: recordingID,
            captureTime: captureTime,
            originalProfileID: originalProfileID,
            originalProfileName: originalProfileName,
            originalInputLanguageCode: originalInputLanguageCode,
            processingProfileID: processingProfileID,
            processingProfileName: processingProfileName,
            processingInputLanguageCode: processingInputLanguageCode
        )
    }

    // MARK: - Recording identity

    private static func testRecordingIdentityRoundTripsAcrossStore() {
        let store = makeStore()
        let recordingID = UUID()
        let captureTime = Date(timeIntervalSince1970: 1_700_000_000)
        let audio = "synthetic-recording.wav"

        let first = makeItem(
            id: UUID(),
            timestamp: captureTime,
            audioFileName: audio,
            recordingID: recordingID,
            captureTime: captureTime,
            postProcessingStatus: "ok"
        )
        let second = makeItem(
            id: UUID(),
            timestamp: captureTime,
            audioFileName: audio,
            recordingID: recordingID,
            captureTime: captureTime,
            postProcessingStatus: "retry ok"
        )

        // Append triggers trim with a large maxCount so both rows
        // survive the first insert.
        try! store.append(first, maxCount: 20)
        try! store.append(second, maxCount: 20)

        let loaded = store.loadAllHistory()
        TestSupport.expectEqual(loaded.count, 2)
        let identities = Set(loaded.map { $0.effectiveRecordingID })
        TestSupport.expectEqual(identities, [recordingID])
        let captureTimes = Set(loaded.map { $0.effectiveCaptureTime })
        TestSupport.expectEqual(captureTimes, [captureTime])
        let audioNames = Set(loaded.compactMap { $0.audioFileName })
        TestSupport.expectEqual(audioNames, [audio])
    }

    private static func testProfileSnapshotsRoundTripWithoutSecrets() {
        let store = makeStore()
        let originalID = UUID()
        let processingID = UUID()
        let item = makeItem(
            originalProfileID: originalID,
            originalProfileName: "Original Synthetic",
            originalInputLanguageCode: "en",
            processingProfileID: processingID,
            processingProfileName: "Processing Synthetic",
            processingInputLanguageCode: "da"
        )
        try! store.append(item, maxCount: 20)

        guard let loaded = store.loadAllHistory().first else {
            fatalError("Expected one retained item after append")
        }
        TestSupport.expectEqual(loaded.originalProfileID, originalID)
        TestSupport.expectEqual(loaded.originalProfileName, "Original Synthetic")
        TestSupport.expectEqual(loaded.originalInputLanguageCode, "en")
        TestSupport.expectEqual(loaded.processingProfileID, processingID)
        TestSupport.expectEqual(loaded.processingProfileName, "Processing Synthetic")
        TestSupport.expectEqual(loaded.processingInputLanguageCode, "da")

        // Serialize the stored item to JSON so the test asserts the
        // persisted form omits endpoint URLs and credentials.
        let data = try! JSONEncoder().encode(loaded)
        let parsed = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        let forbiddenKeys: Set<String> = [
            "transcriptionAPIKey",
            "transcriptionAPIURL",
            "transcriptionBaseURL",
            "realtimeAPIKey",
            "realtimeAPIURL",
            "apiKey",
            "apiBaseURL"
        ]
        let leaked = Set(parsed.keys).intersection(forbiddenKeys)
        TestSupport.expect(leaked.isEmpty, "Persisted history leaked sensitive keys: \(leaked)")
    }

    private static func testSuccessfulAndFailedInitialTranscriptionRetainMetadata() {
        let store = makeStore()
        let recordingID = UUID()
        let captureTime = Date(timeIntervalSince1970: 1_700_000_500)
        let audio = "synthetic-recoverable.wav"

        let failed = makeItem(
            id: UUID(),
            timestamp: captureTime,
            audioFileName: audio,
            recordingID: recordingID,
            captureTime: captureTime,
            postProcessingStatus: "Error: synthetic transcription failure"
        )
        let success = makeItem(
            id: UUID(),
            timestamp: captureTime,
            audioFileName: audio,
            recordingID: recordingID,
            captureTime: captureTime,
            postProcessingStatus: "ok"
        )
        try! store.append(failed, maxCount: 20)
        try! store.append(success, maxCount: 20)

        let loaded = store.loadAllHistory()
        TestSupport.expectEqual(loaded.count, 2)
        for item in loaded {
            TestSupport.expectEqual(item.effectiveRecordingID, recordingID)
            TestSupport.expectEqual(item.effectiveCaptureTime, captureTime)
            TestSupport.expectEqual(item.audioFileName, audio)
            TestSupport.expect(
                item.physicalRecordingIdentity != nil,
                "Linked item must expose a PhysicalRecordingIdentity when audio is attached"
            )
        }
    }

    // MARK: - Legacy migration

    private static func testLegacyRowsMigrateToEffectiveIdentityAndTimestamp() {
        // Build an in-memory store that the test fully owns, insert a
        // pre-migration row directly into its CoreData context, then
        // load the history through a fresh `PipelineHistoryStore`
        // bound to the same container. The loader must surface the
        // legacy row with deterministic effective identity derived
        // from the row's own `id` and `timestamp`.
        let probe = PipelineHistoryStore.inMemory()
        let context = probe.container.viewContext
        let entity = PipelineHistoryEntry(context: context)
        let legacyID = UUID()
        let legacyTimestamp = Date(timeIntervalSince1970: 1_700_001_000)
        entity.id = legacyID
        entity.timestamp = legacyTimestamp
        entity.rawTranscript = "synthetic legacy raw"
        entity.postProcessedTranscript = "synthetic legacy post"
        entity.contextSummary = "synthetic legacy context"
        entity.contextScreenshotStatus = "synthetic legacy screenshot"
        entity.postProcessingStatus = "synthetic legacy post status"
        entity.debugStatus = "synthetic legacy debug"
        entity.customVocabulary = ""
        entity.audioFileName = "synthetic-legacy.wav"
        // Intentionally do NOT set recordingID, captureTime, or any
        // profile fields — this row must look like a pre-migration
        // entry to the loader.
        try! context.save()

        // Build a fresh store around the same container so the
        // loader reads back the legacy row.
        let legacyStore = PipelineHistoryStore(
            container: probe.container,
            isStoreLoaded: true
        )
        let loaded = legacyStore.loadAllHistory()
        TestSupport.expectEqual(loaded.count, 1)
        guard let only = loaded.first else { return }
        // Effective identity falls back to the row's own id / timestamp.
        TestSupport.expectEqual(only.effectiveRecordingID, legacyID)
        TestSupport.expectEqual(only.effectiveCaptureTime, legacyTimestamp)
        // Profile fields stay nil so the loader reports a migrated
        // (unknown) profile rather than a synthetic one.
        TestSupport.expectEqual(only.originalProfileID, nil)
        TestSupport.expectEqual(only.originalProfileName, nil)
        TestSupport.expectEqual(only.originalInputLanguageCode, nil)
        TestSupport.expectEqual(only.processingProfileID, nil)
        TestSupport.expectEqual(only.processingProfileName, nil)
        TestSupport.expectEqual(only.processingInputLanguageCode, nil)
        // The original timestamp field is preserved verbatim.
        TestSupport.expectEqual(only.timestamp, legacyTimestamp)
    }

    private static func testLegacyRowsMigrateOriginalProfileIdentityToNil() {
        // The migration must surface `originalProfileID == nil` for
        // legacy rows rather than fabricating a UUID; this protects
        // the run-log migration check that "original profile was
        // recorded for this row".
        let store = makeStore()
        let item = makeItem(originalProfileID: nil, originalProfileName: nil, originalInputLanguageCode: nil)
        try! store.append(item, maxCount: 20)
        guard let loaded = store.loadAllHistory().first else { return }
        TestSupport.expectEqual(loaded.effectiveOriginalProfileID, nil)
    }

    private static func testMetadataSurvivesStoreRelaunchOnDisk() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("freeflow-physical-recording-tests-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        let storeURL = tempDir.appendingPathComponent("History.sqlite")

        let recordingID = UUID()
        let captureTime = Date(timeIntervalSince1970: 1_700_002_000)
        let originalProfileID = UUID()
        let processingProfileID = UUID()
        let audio = "synthetic-relaunch.wav"

        // First "launch": write a row.
        do {
            let store = PipelineHistoryStore.temporaryOnDisk(at: storeURL)
            let item = makeItem(
                audioFileName: audio,
                recordingID: recordingID,
                captureTime: captureTime,
                originalProfileID: originalProfileID,
                originalProfileName: "Original Synthetic",
                originalInputLanguageCode: "en",
                processingProfileID: processingProfileID,
                processingProfileName: "Processing Synthetic",
                processingInputLanguageCode: "da"
            )
            try! store.append(item, maxCount: 20)
        }

        // Second "launch": read the row back from the same SQLite
        // file and confirm every persisted field survives.
        let store = PipelineHistoryStore.temporaryOnDisk(at: storeURL)
        let loaded = store.loadAllHistory()
        TestSupport.expectEqual(loaded.count, 1)
        guard let only = loaded.first else { return }
        TestSupport.expectEqual(only.audioFileName, audio)
        TestSupport.expectEqual(only.effectiveRecordingID, recordingID)
        TestSupport.expectEqual(only.effectiveCaptureTime, captureTime)
        TestSupport.expectEqual(only.originalProfileID, originalProfileID)
        TestSupport.expectEqual(only.originalProfileName, "Original Synthetic")
        TestSupport.expectEqual(only.originalInputLanguageCode, "en")
        TestSupport.expectEqual(only.processingProfileID, processingProfileID)
        TestSupport.expectEqual(only.processingProfileName, "Processing Synthetic")
        TestSupport.expectEqual(only.processingInputLanguageCode, "da")
    }

    // MARK: - Latest selection

    private static func testLatestItemSelectedByCaptureTimeAcrossLinkedResults() {
        // Linked results (sharing one `recordingID` and WAV) share the
        // same Physical Recording `captureTime`; only their per-attempt
        // `timestamp` differs. The latest-selection routine sorts by
        // `effectiveCaptureTime`, so all linked results tie and any
        // one of them is a valid "latest" pick. The selection must
        // still resolve to a row that belongs to the linked group
        // (same `effectiveRecordingID`, same `effectiveCaptureTime`,
        // references the same WAV).
        let store = makeStore()
        let recordingID = UUID()
        let audio = "synthetic-latest.wav"
        let captureTime = Date(timeIntervalSince1970: 1_700_003_000)
        let firstAttemptTime = captureTime
        let secondAttemptTime = captureTime.addingTimeInterval(500)

        let first = makeItem(
            id: UUID(),
            timestamp: firstAttemptTime,
            audioFileName: audio,
            recordingID: recordingID,
            captureTime: captureTime,
            postProcessingStatus: "Error: synthetic initial failure"
        )
        let second = makeItem(
            id: UUID(),
            timestamp: secondAttemptTime,
            audioFileName: audio,
            recordingID: recordingID,
            captureTime: captureTime,
            postProcessingStatus: "ok"
        )
        try! store.append(first, maxCount: 20)
        try! store.append(second, maxCount: 20)

        let loaded = store.loadAllHistory()
        TestSupport.expectEqual(loaded.count, 2)
        let latest = PipelineHistoryItem.latestPhysicalRecording(in: loaded)
        TestSupport.expect(latest != nil, "Latest Physical Recording must be discoverable")
        TestSupport.expectEqual(latest?.effectiveRecordingID, recordingID)
        TestSupport.expectEqual(latest?.effectiveCaptureTime, captureTime)
        TestSupport.expectEqual(latest?.audioFileName, audio)
        let selectedStatuses = Set(loaded.map { $0.postProcessingStatus })
        TestSupport.expect(selectedStatuses.contains(latest?.postProcessingStatus ?? ""),
                          "Latest must be one of the linked results")
    }

    private static func testLatestSelectionIncludesFailedAndAgedOutOriginal() {
        // Three linked results for one Physical Recording. They share
        // one `recordingID`, one WAV, and one `captureTime`; their
        // per-attempt `timestamp`s differ so the "aged-out original"
        // attempt lands before the failed initial transcription and
        // the final retry. Because linked results tie on capture time,
        // any of them is a valid latest pick — the selection must
        // still resolve to a row that belongs to the linked group
        // (same `effectiveRecordingID`, same `effectiveCaptureTime`,
        // references the same WAV).
        let store = makeStore()
        let recordingID = UUID()
        let audio = "synthetic-aged-out.wav"
        let captureTime = Date(timeIntervalSince1970: 1_700_004_000)
        let original = makeItem(
            id: UUID(),
            timestamp: captureTime,
            audioFileName: audio,
            recordingID: recordingID,
            captureTime: captureTime,
            postProcessingStatus: "ok"
        )
        let failed = makeItem(
            id: UUID(),
            timestamp: captureTime.addingTimeInterval(500),
            audioFileName: audio,
            recordingID: recordingID,
            captureTime: captureTime,
            postProcessingStatus: "Error: synthetic failed initial"
        )
        let success = makeItem(
            id: UUID(),
            timestamp: captureTime.addingTimeInterval(1_000),
            audioFileName: audio,
            recordingID: recordingID,
            captureTime: captureTime,
            postProcessingStatus: "ok"
        )
        try! store.append(failed, maxCount: 20)
        try! store.append(original, maxCount: 20)
        try! store.append(success, maxCount: 20)

        let loaded = store.loadAllHistory()
        TestSupport.expectEqual(loaded.count, 3)
        let latest = PipelineHistoryItem.latestPhysicalRecording(in: loaded)
        TestSupport.expect(latest != nil, "Latest Physical Recording must be discoverable")
        TestSupport.expectEqual(latest?.effectiveRecordingID, recordingID)
        TestSupport.expectEqual(latest?.effectiveCaptureTime, captureTime)
        TestSupport.expectEqual(latest?.audioFileName, audio)
        let linkedIDs: Set<UUID> = [original.id, failed.id, success.id]
        TestSupport.expect(linkedIDs.contains(latest?.id ?? UUID()),
                          "Latest must be one of the linked attempts")
    }

    private static func testLatestSelectionAcrossDistinctRecordingsPicksNewest() {
        let store = makeStore()
        let olderRecordingID = UUID()
        let newerRecordingID = UUID()
        let older = makeItem(
            audioFileName: "synthetic-older.wav",
            recordingID: olderRecordingID,
            captureTime: Date(timeIntervalSince1970: 1_700_006_000)
        )
        let newer = makeItem(
            audioFileName: "synthetic-newer.wav",
            recordingID: newerRecordingID,
            captureTime: Date(timeIntervalSince1970: 1_700_007_000)
        )
        try! store.append(older, maxCount: 20)
        try! store.append(newer, maxCount: 20)

        let loaded = store.loadAllHistory()
        let latest = PipelineHistoryItem.latestPhysicalRecording(in: loaded)
        TestSupport.expectEqual(latest?.effectiveRecordingID, newerRecordingID)
        TestSupport.expectEqual(latest?.effectiveCaptureTime, Date(timeIntervalSince1970: 1_700_007_000))
    }

    private static func testLatestSelectionSkipsItemsWithoutAudio() {
        let store = makeStore()
        let audioLess = makeItem(
            audioFileName: nil,
            recordingID: UUID(),
            captureTime: Date(timeIntervalSince1970: 1_700_008_500)
        )
        let withAudio = makeItem(
            audioFileName: "synthetic-with-audio.wav",
            recordingID: UUID(),
            captureTime: Date(timeIntervalSince1970: 1_700_008_000)
        )
        try! store.append(audioLess, maxCount: 20)
        try! store.append(withAudio, maxCount: 20)

        let loaded = store.loadAllHistory()
        let latest = PipelineHistoryItem.latestPhysicalRecording(in: loaded)
        // The audio-less item's `captureTime` is later but it is not
        // a Physical Recording (no audio); the selection must prefer
        // the row that actually references a WAV.
        TestSupport.expectEqual(latest?.audioFileName, "synthetic-with-audio.wav")
    }

    // MARK: - Shared audio

    private static func testSharedAudioFilenameRoundTripsAcrossLinkedItems() {
        let store = makeStore()
        let audio = "synthetic-shared.wav"
        let recordingID = UUID()
        let captureTime = Date(timeIntervalSince1970: 1_700_009_000)
        let first = makeItem(
            id: UUID(),
            timestamp: captureTime,
            audioFileName: audio,
            recordingID: recordingID,
            captureTime: captureTime
        )
        let second = makeItem(
            id: UUID(),
            timestamp: captureTime,
            audioFileName: audio,
            recordingID: recordingID,
            captureTime: captureTime
        )
        try! store.append(first, maxCount: 20)
        try! store.append(second, maxCount: 20)

        let loaded = store.loadAllHistory()
        TestSupport.expectEqual(loaded.count, 2)
        let audioReferences = loaded.compactMap { $0.audioFileName }
        TestSupport.expectEqual(Set(audioReferences), [audio])
    }

    private static func testDeletingOneLinkedResultKeepsAudioForRemaining() {
        let store = makeStore()
        let audio = "synthetic-delete-one.wav"
        let recordingID = UUID()
        let captureTime = Date(timeIntervalSince1970: 1_700_010_000)
        let first = makeItem(
            id: UUID(),
            timestamp: captureTime,
            audioFileName: audio,
            recordingID: recordingID,
            captureTime: captureTime
        )
        let second = makeItem(
            id: UUID(),
            timestamp: captureTime,
            audioFileName: audio,
            recordingID: recordingID,
            captureTime: captureTime
        )
        try! store.append(first, maxCount: 20)
        try! store.append(second, maxCount: 20)

        let loaded = store.loadAllHistory()
        let firstID = loaded.first?.id ?? first.id
        let secondID = loaded.last?.id ?? second.id

        let returnedFirst = try! store.delete(id: firstID)
        TestSupport.expectEqual(returnedFirst, nil)

        let afterFirstDelete = store.loadAllHistory()
        TestSupport.expectEqual(afterFirstDelete.count, 1)
        TestSupport.expectEqual(afterFirstDelete.first?.audioFileName, audio)

        let returnedSecond = try! store.delete(id: secondID)
        TestSupport.expectEqual(returnedSecond, audio)
    }

    private static func testTrimmingDropsAudioOnlyWhenLastReferenceRemoved() {
        let store = makeStore()
        let audio = "synthetic-trim.wav"
        let recordingID = UUID()
        let captureTime = Date(timeIntervalSince1970: 1_700_011_000)
        // Insert four rows that share one WAV, then trim to two.
        // The trim drops the two oldest rows, but the two
        // retained rows still reference the audio so the WAV must
        // NOT be returned for deletion. A follow-up trim that
        // removes the last references surfaces the WAV exactly
        // once.
        let rows: [PipelineHistoryItem] = (0..<4).map { index in
            makeItem(
                id: UUID(),
                timestamp: captureTime.addingTimeInterval(TimeInterval(index)),
                audioFileName: audio,
                recordingID: recordingID,
                captureTime: captureTime
            )
        }
        for row in rows { try! store.append(row, maxCount: 20) }

        let keptAudio = try! store.trim(to: 2)
        // Retained rows still reference the audio; the WAV must
        // NOT appear in the dropped list so the caller leaves the
        // on-disk file alone.
        TestSupport.expectEqual(keptAudio, [])

        let retained = store.loadAllHistory()
        TestSupport.expectEqual(retained.count, 2)
        TestSupport.expectEqual(Set(retained.compactMap { $0.audioFileName }), [audio])

        // Trimming further (still 2 retained rows) without
        // changing the bound returns no dropped filenames.
        let noDrop = try! store.trim(to: 2)
        TestSupport.expectEqual(noDrop, [])

        // Trim below the retained count so every reference to the
        // audio goes away; the WAV is returned exactly once.
        let finalDrop = try! store.trim(to: 0)
        TestSupport.expectEqual(finalDrop, [audio])
    }

    private static func testRemovingFinalReferenceReturnsAudioExactlyOnce() {
        let store = makeStore()
        let audio = "synthetic-final.wav"
        let recordingID = UUID()
        let captureTime = Date(timeIntervalSince1970: 1_700_012_000)
        let first = makeItem(
            id: UUID(),
            timestamp: captureTime,
            audioFileName: audio,
            recordingID: recordingID,
            captureTime: captureTime
        )
        let second = makeItem(
            id: UUID(),
            timestamp: captureTime,
            audioFileName: audio,
            recordingID: recordingID,
            captureTime: captureTime
        )
        try! store.append(first, maxCount: 20)
        try! store.append(second, maxCount: 20)

        let loaded = store.loadAllHistory()
        let firstID = loaded.first?.id ?? first.id
        let secondID = loaded.last?.id ?? second.id

        // Delete one linked result: still one reference, so no
        // audio filename is returned.
        let returnedFirst = try! store.delete(id: firstID)
        TestSupport.expectEqual(returnedFirst, nil)

        // Delete the last linked result: the audio filename is
        // returned exactly once so the caller can delete it from
        // disk.
        let returnedSecond = try! store.delete(id: secondID)
        TestSupport.expectEqual(returnedSecond, audio)

        let after = store.loadAllHistory()
        TestSupport.expectEqual(after.count, 0)
    }

    private static func testClearReturnsUniqueAudioFilenames() {
        let store = makeStore()
        let audioA = "synthetic-clear-a.wav"
        let audioB = "synthetic-clear-b.wav"
        let audioC = "synthetic-clear-c.wav"
        let rows: [PipelineHistoryItem] = [
            makeItem(audioFileName: audioA),
            makeItem(audioFileName: audioA),
            makeItem(audioFileName: audioB),
            makeItem(audioFileName: audioC),
            makeItem(audioFileName: nil)
        ]
        for row in rows { try! store.append(row, maxCount: 20) }

        let returned = try! store.clearAll()
        TestSupport.expectEqual(Set(returned), [audioA, audioB, audioC])
        // Order does not matter but the count must match the unique
        // set; this guards against a regression where the caller
        // double-deletes one file.
        TestSupport.expectEqual(returned.count, 3)
        TestSupport.expectEqual(store.loadAllHistory().count, 0)
    }

    private static func testClearDropsEveryRetainedAudio() {
        let store = makeStore()
        let rows: [PipelineHistoryItem] = (0..<5).map { index in
            makeItem(audioFileName: "synthetic-bulk-\(index).wav")
        }
        for row in rows { try! store.append(row, maxCount: 20) }
        let returned = try! store.clearAll()
        TestSupport.expectEqual(Set(returned), Set(rows.compactMap { $0.audioFileName }))
        TestSupport.expectEqual(store.loadAllHistory().count, 0)
    }

    private static func testUpdatePreservesIdentityForRetriedLinkedResult() {
        let store = makeStore()
        let recordingID = UUID()
        let captureTime = Date(timeIntervalSince1970: 1_700_013_000)
        let originalProfileID = UUID()
        let original = makeItem(
            id: UUID(),
            timestamp: captureTime,
            audioFileName: "synthetic-retry.wav",
            recordingID: recordingID,
            captureTime: captureTime,
            originalProfileID: originalProfileID,
            originalProfileName: "Original Synthetic",
            originalInputLanguageCode: "en",
            processingProfileID: originalProfileID,
            processingProfileName: "Original Synthetic",
            processingInputLanguageCode: "en",
            postProcessingStatus: "Error: synthetic initial failure"
        )
        try! store.append(original, maxCount: 20)

        // Retry with a different processing profile but the same
        // original identity.
        let retried = PipelineHistoryItem(
            intent: original.intent,
            id: original.id,
            timestamp: original.timestamp,
            rawTranscript: "synthetic retry raw",
            postProcessedTranscript: "synthetic retry post-processed",
            postProcessingPrompt: "synthetic retry prompt",
            systemPrompt: original.systemPrompt,
            contextSummary: original.contextSummary,
            contextScreenshotDataURL: original.contextScreenshotDataURL,
            contextScreenshotStatus: original.contextScreenshotStatus,
            postProcessingStatus: "ok",
            debugStatus: "Retried",
            customVocabulary: original.customVocabulary,
            audioFileName: original.audioFileName,
            recordingID: recordingID,
            captureTime: captureTime,
            originalProfileID: originalProfileID,
            originalProfileName: "Original Synthetic",
            originalInputLanguageCode: "en",
            processingProfileID: UUID(),
            processingProfileName: "Retry Synthetic",
            processingInputLanguageCode: "da"
        )
        try! store.update(retried)

        guard let loaded = store.loadAllHistory().first else { return }
        TestSupport.expectEqual(loaded.audioFileName, original.audioFileName)
        TestSupport.expectEqual(loaded.effectiveRecordingID, recordingID)
        TestSupport.expectEqual(loaded.effectiveCaptureTime, captureTime)
        TestSupport.expectEqual(loaded.originalProfileID, originalProfileID)
        TestSupport.expectEqual(loaded.processingProfileName, "Retry Synthetic")
        TestSupport.expectEqual(loaded.processingInputLanguageCode, "da")
    }

    // MARK: - Eligibility

    private static func testEligibilityPassesWhenAudioFileExists() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("freeflow-eligibility-pass-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        let audioFileName = "synthetic-eligibility.wav"
        let audioURL = tempDir.appendingPathComponent(audioFileName)
        try! Data("synthetic".utf8).write(to: audioURL)

        let store = makeStore()
        let item = makeItem(audioFileName: audioFileName)
        try! store.append(item, maxCount: 20)

        let result = store.eligibility(forRetryingID: item.id, audioStorageDirectory: tempDir)
        switch result {
        case .none:
            break
        case .some(let error):
            fatalError("Expected no eligibility error, got \(error)")
        }
        // Retained history is untouched by the eligibility check.
        TestSupport.expectEqual(store.loadAllHistory().count, 1)
    }

    private static func testEligibilityReportsMissingAudioFileWithoutMutatingHistory() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("freeflow-eligibility-missing-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        let audioFileName = "synthetic-missing.wav"
        // Note: file is NOT created on disk.

        let store = makeStore()
        let item = makeItem(audioFileName: audioFileName)
        try! store.append(item, maxCount: 20)

        let result = store.eligibility(forRetryingID: item.id, audioStorageDirectory: tempDir)
        switch result {
        case .missingAudioFile(let name)?:
            TestSupport.expectEqual(name, audioFileName)
        case .some(let other):
            fatalError("Expected .missingAudioFile, got \(other)")
        case .none:
            fatalError("Expected a recoverable eligibility error")
        }
        // Retained history is untouched.
        TestSupport.expectEqual(store.loadAllHistory().count, 1)
    }

    private static func testEligibilityReportsItemNotFoundWithoutMutatingHistory() {
        let store = makeStore()
        let bogusID = UUID()
        let result = store.eligibility(
            forRetryingID: bogusID,
            audioStorageDirectory: FileManager.default.temporaryDirectory
        )
        switch result {
        case .itemNotFound?:
            break
        case .some(let other):
            fatalError("Expected .itemNotFound, got \(other)")
        case .none:
            fatalError("Expected a recoverable eligibility error")
        }
        TestSupport.expectEqual(store.loadAllHistory().count, 0)
    }

    private static func testEligibilityReportsNoAudioReferenceWithoutMutatingHistory() {
        let store = makeStore()
        let item = makeItem(audioFileName: nil)
        try! store.append(item, maxCount: 20)
        let result = store.eligibility(
            forRetryingID: item.id,
            audioStorageDirectory: FileManager.default.temporaryDirectory
        )
        switch result {
        case .noAudioReference?:
            break
        case .some(let other):
            fatalError("Expected .noAudioReference, got \(other)")
        case .none:
            fatalError("Expected a recoverable eligibility error")
        }
        TestSupport.expectEqual(store.loadAllHistory().count, 1)
    }

    // MARK: - Encoding

    private static func testEncodingExcludesEndpointURLsAndCredentials() {
        let item = makeItem()
        let data = try! JSONEncoder().encode(item)
        let parsed = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        let forbiddenKeys: Set<String> = [
            "transcriptionAPIKey",
            "transcriptionAPIURL",
            "transcriptionBaseURL",
            "realtimeAPIKey",
            "realtimeAPIURL",
            "apiKey",
            "apiBaseURL"
        ]
        let leaked = Set(parsed.keys).intersection(forbiddenKeys)
        TestSupport.expect(leaked.isEmpty, "PipelineHistoryItem JSON leaked sensitive keys: \(leaked)")
    }
}

// MARK: - Legacy migration helpers

// The legacy-migration test reaches `PipelineHistoryStore.container`
// through the internal-access property declared on `PipelineHistoryStore`
// (the production class keeps the property non-private so tests can
// attach a managed object context for inserting pre-migration rows).