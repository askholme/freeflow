enum LocalTranscriptionPolicyTests {
    static func run() {
        let local = LocalTranscriptionPolicy(isEnabled: true)
        TestSupport.expect(!local.allowsRealtimeStreaming, "Local mode allowed realtime streaming")

        let remote = LocalTranscriptionPolicy(isEnabled: false)
        TestSupport.expect(remote.allowsRealtimeStreaming, "Remote mode lost realtime streaming")

        // Context capture and language-model processing are no longer part of
        // the transcription policy: they are user-toggled cleanup concerns.
        // The policy only governs transcription-routing decisions.
    }
}
