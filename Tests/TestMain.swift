import Foundation

@main
struct FreeFlowTests {
    static func main() async {
        AppContextServiceTests.run()
        ModelConfigurationTests.run()
        ShortcutCoreTests.run()
        SemanticVersionTests.run()
        LLMCooldownManagerTests.run()
        LocalParakeetModelStoreTests.run()
        await LocalParakeetTranscriptionServiceTests.run()
        LocalTranscriptionPolicyTests.run()
        PipelineStageToggleTests.run()
        TranscriptTextCoreTests.run()
        print("FreeFlowTests passed")
    }
}
