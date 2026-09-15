import Foundation

enum PipelineHistoryItemIntent: String, Codable {
    case dictation
    case commandAutomatic = "command:automatic"
    case commandManual = "command:manual"
}

/// Stable identity shared by every `PipelineHistoryItem` that was
/// processed from the same saved audio file. The recording identity
/// is captured at recording start and is never mutated for the
/// lifetime of the persisted `PipelineHistoryItem`s, so every
/// Processing Attempt that shares the WAV is linkable across history
/// loads.
///
/// The three fields here are the smallest possible identity tuple:
/// - `recordingID` identifies one Physical Recording
/// - `captureTime` is the moment audio capture started (shared by
///   every linked Processing Attempt)
/// - `audioFileName` is the on-disk WAV that backs every linked
///   Processing Attempt.
///
/// Endpoint URLs, API keys, and other secrets are deliberately
/// absent so identity survives history persistence without leaking
/// any sensitive value.
struct PhysicalRecordingIdentity: Codable, Equatable {
    let recordingID: UUID
    let captureTime: Date
    let audioFileName: String
}

/// Per-Processing Attempt profile snapshot. Each Processing Attempt
/// is processed with its own resolved Language Profile; the snapshot
/// stored alongside the persisted item lets the run log show which
/// profile produced the transcript without re-resolving against
/// today's settings.
///
/// Like `PhysicalRecordingIdentity`, endpoint URLs and credentials
/// are intentionally absent. Only the user-presentable profile
/// identity, display name, and input language snapshot travel
/// through history.
struct ProcessingAttemptProfileSnapshot: Codable, Equatable {
    let profileID: UUID
    let profileName: String
    let inputLanguageCode: String
}

struct PipelineHistoryItem: Identifiable, Codable {
    let intent: PipelineHistoryItemIntent
    let selectedText: String?
    let capturedSelection: String?
    let id: UUID
    let timestamp: Date
    let rawTranscript: String
    let postProcessedTranscript: String
    let postProcessingPrompt: String?
    let systemPrompt: String?
    let contextSummary: String
    let contextSystemPrompt: String?
    let contextPrompt: String?
    let contextScreenshotDataURL: String?
    let contextScreenshotStatus: String
    let postProcessingStatus: String
    let debugStatus: String
    let customVocabulary: String
    let audioFileName: String?
    let contextAppName: String?
    let contextBundleIdentifier: String?
    let contextWindowTitle: String?

    /// Physical Recording identity shared by every linked Processing
    /// Attempt. Nil when this entry was persisted before the
    /// Physical Recording identity was introduced; the store layer
    /// migrates legacy rows to a deterministic effective identity
    /// (`recordingID == id`, `captureTime == timestamp`).
    let recordingID: UUID?
    /// Capture time shared by every linked Processing Attempt.
    /// Migrated to `timestamp` for legacy rows.
    let captureTime: Date?
    /// Original Language Profile active when audio capture started.
    /// Used by the run log and the eligibility check to identify the
    /// profile whose configuration owns the recorded audio.
    let originalProfileID: UUID?
    let originalProfileName: String?
    let originalInputLanguageCode: String?
    /// Per-Processing Attempt Language Profile snapshot — the profile
    /// whose configuration actually produced this attempt's
    /// transcript.
    let processingProfileID: UUID?
    let processingProfileName: String?
    let processingInputLanguageCode: String?

    init(
        intent: PipelineHistoryItemIntent = .dictation,
        selectedText: String? = nil,
        capturedSelection: String? = nil,
        id: UUID = UUID(),
        timestamp: Date,
        rawTranscript: String,
        postProcessedTranscript: String,
        postProcessingPrompt: String?,
        systemPrompt: String? = nil,
        contextSummary: String,
        contextSystemPrompt: String? = nil,
        contextPrompt: String? = nil,
        contextScreenshotDataURL: String?,
        contextScreenshotStatus: String,
        postProcessingStatus: String,
        debugStatus: String,
        customVocabulary: String,
        audioFileName: String? = nil,
        contextAppName: String? = nil,
        contextBundleIdentifier: String? = nil,
        contextWindowTitle: String? = nil,
        recordingID: UUID? = nil,
        captureTime: Date? = nil,
        originalProfileID: UUID? = nil,
        originalProfileName: String? = nil,
        originalInputLanguageCode: String? = nil,
        processingProfileID: UUID? = nil,
        processingProfileName: String? = nil,
        processingInputLanguageCode: String? = nil
    ) {
        self.intent = intent
        self.selectedText = selectedText
        self.capturedSelection = capturedSelection
        self.id = id
        self.timestamp = timestamp
        self.rawTranscript = rawTranscript
        self.postProcessedTranscript = postProcessedTranscript
        self.postProcessingPrompt = postProcessingPrompt
        self.systemPrompt = systemPrompt
        self.contextSummary = contextSummary
        self.contextSystemPrompt = contextSystemPrompt
        self.contextPrompt = contextPrompt
        self.contextScreenshotDataURL = contextScreenshotDataURL
        self.contextScreenshotStatus = contextScreenshotStatus
        self.postProcessingStatus = postProcessingStatus
        self.debugStatus = debugStatus
        self.customVocabulary = customVocabulary
        self.audioFileName = audioFileName
        self.contextAppName = contextAppName
        self.contextBundleIdentifier = contextBundleIdentifier
        self.contextWindowTitle = contextWindowTitle
        self.recordingID = recordingID
        self.captureTime = captureTime
        self.originalProfileID = originalProfileID
        self.originalProfileName = originalProfileName
        self.originalInputLanguageCode = originalInputLanguageCode
        self.processingProfileID = processingProfileID
        self.processingProfileName = processingProfileName
        self.processingInputLanguageCode = processingInputLanguageCode
    }

    // MARK: - Effective accessors

    /// Effective `recordingID` after legacy migration. New writes
    /// always populate `recordingID` directly; rows persisted before
    /// Physical Recording identity existed fall back to the entry's
    /// own `id` so every retained item is reachable through a stable
    /// identity even when no other field is populated.
    var effectiveRecordingID: UUID {
        recordingID ?? id
    }

    /// Effective `captureTime` after legacy migration. New writes
    /// always populate `captureTime` directly; legacy rows fall back
    /// to the entry's own `timestamp` so existing history remains
    /// sortable without destructive rewriting.
    var effectiveCaptureTime: Date {
        captureTime ?? timestamp
    }

    /// Migrated `originalProfileID`. Nil for legacy rows where no
    /// original-profile metadata was recorded.
    var effectiveOriginalProfileID: UUID? {
        originalProfileID
    }

    /// Effective Physical Recording identity bundle after legacy
    /// migration. Returns nil when no audio is attached (a row with
    /// no WAV is not a Physical Recording).
    var physicalRecordingIdentity: PhysicalRecordingIdentity? {
        guard let audioFileName else { return nil }
        return PhysicalRecordingIdentity(
            recordingID: effectiveRecordingID,
            captureTime: effectiveCaptureTime,
            audioFileName: audioFileName
        )
    }

    /// Effective per-Processing Attempt profile. Nil when no
    /// processing-profile metadata was recorded (legacy rows and
    /// rows that never recorded one).
    var processingAttemptProfile: ProcessingAttemptProfileSnapshot? {
        guard let profileID = processingProfileID,
              let profileName = processingProfileName,
              let inputLanguageCode = processingInputLanguageCode else {
            return nil
        }
        return ProcessingAttemptProfileSnapshot(
            profileID: profileID,
            profileName: profileName,
            inputLanguageCode: inputLanguageCode
        )
    }
}

extension PipelineHistoryItem {
    /// Pick the item with the latest `effectiveCaptureTime` from
    /// `items`. Only items that actually reference a saved WAV are
    /// considered (a row with no audio is not a Physical Recording).
    /// Returns nil for an empty input.
    static func latestPhysicalRecording(in items: [PipelineHistoryItem]) -> PipelineHistoryItem? {
        items
            .filter { $0.audioFileName != nil && !($0.audioFileName?.isEmpty ?? true) }
            .max(by: { $0.effectiveCaptureTime < $1.effectiveCaptureTime })
    }
}
