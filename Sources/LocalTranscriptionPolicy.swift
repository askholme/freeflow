struct LocalTranscriptionPolicy: Equatable {
    let isEnabled: Bool

    /// On-device transcription deliberately ignores realtime streaming: the
    /// local recogniser emits a finished transcript on stop, not partials.
    var allowsRealtimeStreaming: Bool { !isEnabled }
}
