import Foundation

/// Deterministic tests for the Language Profile catalog, migration,
/// resolution, prompt scope, translation independence, and snapshot
/// immutability contracts. Tests use only invented synthetic values:
/// no real user data, no real `UserDefaults`, and no real credential
/// storage. A small in-memory `LanguageProfileCredentialStore`
/// conformance injects credentials into the resolver.
enum LanguageProfileTests {

    /// Dictionary-backed `LanguageProfileCredentialStore` used to inject
    /// credentials into the resolver for tests. Production code uses
    /// `AppSettingsStorageLanguageProfileCredentialStore`; the test
    /// boundary is intentionally different so tests never touch real
    /// credentials or persistent storage.
    private final class InMemoryCredentialStore: LanguageProfileCredentialStore {
        private var values: [UUID: String]

        init(values: [UUID: String] = [:]) {
            self.values = values
        }

        func loadAPIKeyOverride(profileID: UUID) -> String? {
            values[profileID]
        }

        func setAPIKeyOverride(_ value: String, profileID: UUID) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            values[profileID] = trimmed
        }

        func clearAPIKeyOverride(profileID: UUID) {
            values.removeValue(forKey: profileID)
        }
    }

    static func run() {
        testEncodingExcludesCredentials()
        testSupportedLanguagesCovered()
        testMigrationSeedsOneProfileForLegacyDanish()
        testMigrationSeedsAutoDetectForEmptyLegacy()
        testMigrationNormalizesUnsupportedLegacy()
        testMigrationPreservesEffectiveBehavior()
        testLoadRepairDropsInvalidEntries()
        testLoadKeepsValidCatalogWithoutRepair()
        testAlwaysAtLeastOneProfileRemains()
        testActiveIDRepairToFirstProfile()
        testResolutionAppliesOverridesAndTrimsWhitespace()
        testResolutionUsesInjectedCredentialOverride()
        testResolutionAutoDetectHasNilLanguageHint()
        testPromptScopeHonorsProfileOverrideOnlyForOrdinary()
        testPromptScopeFallsBackToGlobalCustomPrompt()
        testTranslationIndependence()
        testSnapshotImmutability()
        testAddProfileSuccessAndBecomesActive()
        testAddProfileRejectsEmptyName()
        testAddProfileRejectsUnsupportedCode()
        testAddProfileRejectsDuplicateName()
        testAddProfileRejectsDuplicateLanguageCode()
        testAddProfileRejectsSecondAutoDetect()
        testAddProfileDanishCodePath()
        testRenameProfileSuccessAndTrims()
        testRenameProfileRejectsEmptyName()
        testRenameProfileRejectsDuplicateName()
        testRenameProfileRejectsUnknownID()
        testRenameProfileSameNameIsNoOp()
        testReorderProfileMovesUpAndDown()
        testReorderProfileRejectsTopUp()
        testReorderProfileRejectsBottomDown()
        testReorderProfileRejectsUnknownID()
        testDeleteProfileRejectsFinalProfile()
        testDeleteProfileRejectsUnknownID()
        testDeleteProfileRemovesCredentialOverride()
        testDeleteActiveProfileSelectsSuccessorInOrder()
        testDeleteLastProfileSelectsLastRemaining()
        testCycleActiveProfileAdvancesToNextInOrder()
        testCycleActiveProfileWrapsAtEnd()
        testCycleActiveProfileSingleProfileIsNoOpButReportsProfile()
        testShouldRejectSwitchLanguageTriggerBusyRejection()
        testSelectProfileSuccess()
        testSelectProfileRejectsUnknownID()
        testUpdateProfileOverridesTrimsAndPersists()
        testUpdateProfileRejectsDuplicateName()
        testUpdateProfileRejectsDuplicateLanguageCode()
        testSetAPIKeyOverridePersistsThroughStore()
        testClearAPIKeyOverrideRemovesFromStore()
        testEffectiveCleanupPromptUsesProfileOverride()
        testEffectiveCleanupPromptFallsBackToGlobal()
        testEffectiveCleanupPromptFallsBackToBuiltIn()
        testEffectiveTranscriptionValuesFollowOverrideRules()
        testLiveAttemptConfiguresRealtimeWhenGloballyEnabled()
        testLiveAttemptSkipsRealtimeWhenGloballyDisabled()
        testLiveAttemptSkipsRealtimeWhenLocalPolicyEnabled()
        testLiveAttemptSkipsRealtimeWhenCapturedEndpointEmpty()
        testLiveAttemptUsesCapturedProfileEndpointCredentialModelAndLanguage()
        testLiveAttemptUploadFallbackMatchesRealtimeConfiguration()
        testLiveAttemptIsImmutableAcrossSettingsEdits()
        testLiveAttemptLocalTranscriptionUsesLanguageHintOnly()
        testLiveAttemptCapturesTranscriptionMode()
        testLiveAttemptTranslationIndependence()
    }

    // MARK: - Encoding

    private static func testEncodingExcludesCredentials() {
        let syntheticCredential = "sk-test-synthetic-credential-do-not-use"
        let profileID = UUID()
        let credentials = InMemoryCredentialStore(values: [profileID: syntheticCredential])

        let profiles = [
            LanguageProfile(
                id: profileID,
                name: "English",
                inputLanguageCode: "en",
                transcriptionURLOverride: "https://synthetic.example/v1",
                transcriptionModelOverride: "whisper-large-v3",
                realtimeModelOverride: "whisper-large-v3",
                postProcessingPromptOverride: "synthetic prompt override"
            )
        ]

        let data = try! JSONEncoder().encode(profiles)
        let parsed = try! JSONSerialization.jsonObject(with: data) as! [[String: Any]]
        TestSupport.expectEqual(parsed.count, 1)
        let expectedKeys: Set<String> = [
            "id",
            "name",
            "inputLanguageCode",
            "transcriptionURLOverride",
            "transcriptionModelOverride",
            "realtimeModelOverride",
            "postProcessingPromptOverride"
        ]
        TestSupport.expectEqual(Set(parsed[0].keys), expectedKeys)
        let raw = String(data: data, encoding: .utf8) ?? ""
        TestSupport.expect(
            !raw.contains(syntheticCredential),
            "Encoded profile JSON leaked the credential string"
        )

        // Confirm the credential still lives in the injected store so we
        // know the absence in the encoded data is not because we forgot
        // to seed it.
        TestSupport.expectEqual(
            credentials.loadAPIKeyOverride(profileID: profileID),
            syntheticCredential
        )

        // Round-trip the profile through encoding to confirm decode
        // recovers the same fields without the credential.
        let decoded = try! JSONDecoder().decode([LanguageProfile].self, from: data)
        TestSupport.expectEqual(decoded, profiles)
    }

    // MARK: - Supported languages

    private static func testSupportedLanguagesCovered() {
        let languages = LanguageProfiles.supportedInputLanguages
        TestSupport.expect(!languages.isEmpty, "Supported language list must not be empty")
        TestSupport.expectEqual(languages.first?.code, "")
        TestSupport.expectEqual(languages.first?.name, "Auto-detect")
        TestSupport.expect(
            languages.contains(where: { $0.code == "da" && $0.name == "Danish" }),
            "Danish must be a supported input language"
        )
        let codes = languages.map(\.code)
        TestSupport.expect(
            Set(codes).count == codes.count,
            "Supported language codes must be unique"
        )
    }

    // MARK: - Migration

    private static func testMigrationSeedsOneProfileForLegacyDanish() {
        let result = LanguageProfiles.loadCatalog(
            from: LanguageProfiles.StoredLanguageProfileState(
                profilesData: nil,
                activeProfileID: nil,
                legacyTranscriptionLanguage: "da"
            )
        )
        TestSupport.expect(result.didRepairStoredValue, "Seeding the default profile must report repair")
        TestSupport.expectEqual(result.catalog.profiles.count, 1)
        let seeded = result.catalog.profiles[0]
        TestSupport.expectEqual(seeded.name, "Default")
        TestSupport.expectEqual(seeded.inputLanguageCode, "da")
        TestSupport.expectEqual(seeded.transcriptionURLOverride, "")
        TestSupport.expectEqual(seeded.transcriptionModelOverride, "")
        TestSupport.expectEqual(seeded.realtimeModelOverride, "")
        TestSupport.expectEqual(seeded.postProcessingPromptOverride, "")
        TestSupport.expectEqual(result.catalog.activeProfileID, seeded.id)
    }

    private static func testMigrationSeedsAutoDetectForEmptyLegacy() {
        let result = LanguageProfiles.loadCatalog(
            from: LanguageProfiles.StoredLanguageProfileState(
                profilesData: nil,
                activeProfileID: nil,
                legacyTranscriptionLanguage: ""
            )
        )
        TestSupport.expect(result.didRepairStoredValue, "Seeding the default profile must report repair")
        TestSupport.expectEqual(result.catalog.profiles.count, 1)
        TestSupport.expectEqual(result.catalog.profiles[0].inputLanguageCode, "")
    }

    private static func testMigrationNormalizesUnsupportedLegacy() {
        let uppercased = LanguageProfiles.loadCatalog(
            from: LanguageProfiles.StoredLanguageProfileState(
                profilesData: nil,
                activeProfileID: nil,
                legacyTranscriptionLanguage: "DA"
            )
        )
        TestSupport.expectEqual(uppercased.catalog.profiles[0].inputLanguageCode, "da")

        let unsupported = LanguageProfiles.loadCatalog(
            from: LanguageProfiles.StoredLanguageProfileState(
                profilesData: nil,
                activeProfileID: nil,
                legacyTranscriptionLanguage: "xx"
            )
        )
        TestSupport.expectEqual(unsupported.catalog.profiles[0].inputLanguageCode, "")
    }

    private static func testMigrationPreservesEffectiveBehavior() {
        let seeded = LanguageProfiles.loadCatalog(
            from: LanguageProfiles.StoredLanguageProfileState(
                profilesData: nil,
                activeProfileID: nil,
                legacyTranscriptionLanguage: "da"
            )
        )
        let globals = LanguageProfileGlobalDefaults(
            transcriptionBaseURL: "https://synthetic.example/v1",
            transcriptionAPIKey: "synthetic-global-key",
            transcriptionModel: "whisper-large-v3",
            realtimeModel: "whisper-large-v3",
            customSystemPrompt: "global synthetic prompt"
        )
        let credentials = InMemoryCredentialStore()
        let snapshot = seeded.catalog.resolvedActiveProfile(
            globalDefaults: globals,
            credentials: credentials
        )
        TestSupport.expectEqual(snapshot.transcriptionBaseURL, globals.transcriptionBaseURL)
        TestSupport.expectEqual(snapshot.transcriptionAPIKey, globals.transcriptionAPIKey)
        TestSupport.expectEqual(snapshot.transcriptionModel, globals.transcriptionModel)
        TestSupport.expectEqual(snapshot.realtimeModel, globals.realtimeModel)
        TestSupport.expectEqual(snapshot.ordinaryCleanupSystemPrompt, globals.customSystemPrompt)

        let emptyPrompt = seeded.catalog.resolvedActiveProfile(
            globalDefaults: LanguageProfileGlobalDefaults(
                transcriptionBaseURL: globals.transcriptionBaseURL,
                transcriptionAPIKey: globals.transcriptionAPIKey,
                transcriptionModel: globals.transcriptionModel,
                realtimeModel: globals.realtimeModel,
                customSystemPrompt: ""
            ),
            credentials: credentials
        )
        TestSupport.expect(
            emptyPrompt.ordinaryCleanupSystemPrompt == "",
            "Empty global prompt must surface as empty so post-processing uses its built-in default"
        )
    }

    // MARK: - Load / repair

    private static func testLoadRepairDropsInvalidEntries() {
        let first = UUID()
        let second = UUID()
        let duplicatedID = first
        let klingonID = UUID()
        let danishID = UUID()
        let profiles: [LanguageProfile] = [
            LanguageProfile(
                id: first,
                name: "  English ",
                inputLanguageCode: " EN ",
                transcriptionURLOverride: "  https://synthetic.example/v1 ",
                transcriptionModelOverride: " whisper-large-v3 ",
                realtimeModelOverride: " ",
                postProcessingPromptOverride: "  trim me  "
            ),
            // Empty trimmed name should be dropped.
            LanguageProfile(
                id: UUID(),
                name: "   ",
                inputLanguageCode: "fr",
                transcriptionURLOverride: "",
                transcriptionModelOverride: "",
                realtimeModelOverride: "",
                postProcessingPromptOverride: ""
            ),
            // Case-insensitive duplicate name should be dropped.
            LanguageProfile(
                id: second,
                name: "english",
                inputLanguageCode: "es",
                transcriptionURLOverride: "",
                transcriptionModelOverride: "",
                realtimeModelOverride: "",
                postProcessingPromptOverride: ""
            ),
            // Duplicate input-language code should be dropped.
            LanguageProfile(
                id: UUID(),
                name: "German",
                inputLanguageCode: "en",
                transcriptionURLOverride: "",
                transcriptionModelOverride: "",
                realtimeModelOverride: "",
                postProcessingPromptOverride: ""
            ),
            // Unsupported language codes normalize to Auto-detect. This
            // profile is kept unless another Auto-detect profile already
            // exists (at most one Auto-detect profile).
            LanguageProfile(
                id: klingonID,
                name: "Klingon",
                inputLanguageCode: "tlh",
                transcriptionURLOverride: "",
                transcriptionModelOverride: "",
                realtimeModelOverride: "",
                postProcessingPromptOverride: ""
            ),
            // Duplicate UUID should be dropped.
            LanguageProfile(
                id: duplicatedID,
                name: "English Duplicate",
                inputLanguageCode: "en",
                transcriptionURLOverride: "",
                transcriptionModelOverride: "",
                realtimeModelOverride: "",
                postProcessingPromptOverride: ""
            ),
            // A second Auto-detect profile collides on the normalized
            // empty code (the Klingon profile above already normalized to
            // Auto-detect), so this entry must be dropped to enforce the
            // "at most one Auto-detect profile" rule.
            LanguageProfile(
                id: UUID(),
                name: "Auto Too",
                inputLanguageCode: "",
                transcriptionURLOverride: "",
                transcriptionModelOverride: "",
                realtimeModelOverride: "",
                postProcessingPromptOverride: ""
            ),
            LanguageProfile(
                id: danishID,
                name: "Danish",
                inputLanguageCode: "da",
                transcriptionURLOverride: "",
                transcriptionModelOverride: "",
                realtimeModelOverride: "",
                postProcessingPromptOverride: ""
            )
        ]
        let data = try! JSONEncoder().encode(profiles)
        let result = LanguageProfiles.loadCatalog(
            from: LanguageProfiles.StoredLanguageProfileState(
                profilesData: data,
                activeProfileID: first.uuidString,
                legacyTranscriptionLanguage: ""
            )
        )
        TestSupport.expect(result.didRepairStoredValue, "Invalid entries require a repair pass")
        // Survivors in input order: the first English profile (kept,
        // normalized), the Klingon profile (unsupported code normalizes
        // to Auto-detect and no other Auto-detect has been kept yet), and
        // the Danish profile. Dropped: whitespace name, duplicate
        // lowercase "english" name, duplicate "en" code, duplicate UUID,
        // and the "Auto Too" entry (duplicate Auto-detect code).
        TestSupport.expectEqual(result.catalog.profiles.count, 3)
        TestSupport.expectEqual(result.catalog.profiles.map(\.id), [first, klingonID, danishID])
        TestSupport.expectEqual(result.catalog.profiles[0].name, "English")
        TestSupport.expectEqual(result.catalog.profiles[0].inputLanguageCode, "en")
        TestSupport.expectEqual(result.catalog.profiles[0].transcriptionURLOverride, "https://synthetic.example/v1")
        TestSupport.expectEqual(result.catalog.profiles[0].transcriptionModelOverride, "whisper-large-v3")
        TestSupport.expectEqual(result.catalog.profiles[0].realtimeModelOverride, "")
        TestSupport.expectEqual(result.catalog.profiles[0].postProcessingPromptOverride, "trim me")
        TestSupport.expectEqual(result.catalog.profiles[1].name, "Klingon")
        TestSupport.expectEqual(result.catalog.profiles[1].inputLanguageCode, "")
        TestSupport.expectEqual(result.catalog.profiles[2].name, "Danish")
        TestSupport.expectEqual(result.catalog.profiles[2].inputLanguageCode, "da")
        TestSupport.expectEqual(result.catalog.activeProfileID, first)
    }

    private static func testLoadKeepsValidCatalogWithoutRepair() {
        let profileID = UUID()
        let profiles = [
            LanguageProfile(
                id: profileID,
                name: "English",
                inputLanguageCode: "en",
                transcriptionURLOverride: "https://synthetic.example/v1",
                transcriptionModelOverride: "whisper-large-v3",
                realtimeModelOverride: "whisper-large-v3",
                postProcessingPromptOverride: "synthetic prompt"
            )
        ]
        let data = try! JSONEncoder().encode(profiles)
        let result = LanguageProfiles.loadCatalog(
            from: LanguageProfiles.StoredLanguageProfileState(
                profilesData: data,
                activeProfileID: profileID.uuidString,
                legacyTranscriptionLanguage: "en"
            )
        )
        TestSupport.expect(!result.didRepairStoredValue, "Valid catalog must not report repair")
        TestSupport.expectEqual(result.catalog.profiles, profiles)
        TestSupport.expectEqual(result.catalog.activeProfileID, profileID)
    }

    private static func testAlwaysAtLeastOneProfileRemains() {
        let profiles = [
            LanguageProfile(
                id: UUID(),
                name: "   ",
                inputLanguageCode: "xx",
                transcriptionURLOverride: "",
                transcriptionModelOverride: "",
                realtimeModelOverride: "",
                postProcessingPromptOverride: ""
            )
        ]
        let data = try! JSONEncoder().encode(profiles)
        let result = LanguageProfiles.loadCatalog(
            from: LanguageProfiles.StoredLanguageProfileState(
                profilesData: data,
                activeProfileID: UUID().uuidString,
                legacyTranscriptionLanguage: "da"
            )
        )
        TestSupport.expect(result.didRepairStoredValue, "Seeding from invalid entries must report repair")
        TestSupport.expectEqual(result.catalog.profiles.count, 1)
        TestSupport.expectEqual(result.catalog.profiles[0].name, "Default")
        TestSupport.expectEqual(result.catalog.profiles[0].inputLanguageCode, "da")
        TestSupport.expectEqual(result.catalog.activeProfileID, result.catalog.profiles[0].id)
    }

    // MARK: - Active ID repair

    private static func testActiveIDRepairToFirstProfile() {
        let first = UUID()
        let second = UUID()
        let profiles = [
            LanguageProfile(
                id: first,
                name: "English",
                inputLanguageCode: "en",
                transcriptionURLOverride: "",
                transcriptionModelOverride: "",
                realtimeModelOverride: "",
                postProcessingPromptOverride: ""
            ),
            LanguageProfile(
                id: second,
                name: "Danish",
                inputLanguageCode: "da",
                transcriptionURLOverride: "",
                transcriptionModelOverride: "",
                realtimeModelOverride: "",
                postProcessingPromptOverride: ""
            )
        ]
        let data = try! JSONEncoder().encode(profiles)

        let missing = LanguageProfiles.loadCatalog(
            from: LanguageProfiles.StoredLanguageProfileState(
                profilesData: data,
                activeProfileID: nil,
                legacyTranscriptionLanguage: ""
            )
        )
        TestSupport.expectEqual(missing.catalog.activeProfileID, first)
        TestSupport.expect(missing.didRepairStoredValue, "Missing active ID must report repair")

        let malformed = LanguageProfiles.loadCatalog(
            from: LanguageProfiles.StoredLanguageProfileState(
                profilesData: data,
                activeProfileID: "not-a-uuid",
                legacyTranscriptionLanguage: ""
            )
        )
        TestSupport.expectEqual(malformed.catalog.activeProfileID, first)
        TestSupport.expect(malformed.didRepairStoredValue, "Malformed active ID must report repair")

        let unknown = LanguageProfiles.loadCatalog(
            from: LanguageProfiles.StoredLanguageProfileState(
                profilesData: data,
                activeProfileID: UUID().uuidString,
                legacyTranscriptionLanguage: ""
            )
        )
        TestSupport.expectEqual(unknown.catalog.activeProfileID, first)
        TestSupport.expect(unknown.didRepairStoredValue, "Unknown active ID must report repair")

        let valid = LanguageProfiles.loadCatalog(
            from: LanguageProfiles.StoredLanguageProfileState(
                profilesData: data,
                activeProfileID: second.uuidString,
                legacyTranscriptionLanguage: ""
            )
        )
        TestSupport.expectEqual(valid.catalog.activeProfileID, second)
        TestSupport.expect(!valid.didRepairStoredValue, "Valid active ID must not report repair")
    }

    // MARK: - Resolution

    private static func testResolutionAppliesOverridesAndTrimsWhitespace() {
        let profile = LanguageProfile(
            id: UUID(),
            name: "Profile",
            inputLanguageCode: "en",
            transcriptionURLOverride: "  https://synthetic.example/profile-v1  ",
            transcriptionModelOverride: "   ",
            realtimeModelOverride: "profile-realtime-model",
            postProcessingPromptOverride: "  profile prompt  "
        )
        let globals = LanguageProfileGlobalDefaults(
            transcriptionBaseURL: "https://synthetic.example/global-v1",
            transcriptionAPIKey: "global-key",
            transcriptionModel: "global-upload-model",
            realtimeModel: "global-realtime-model",
            customSystemPrompt: "global prompt"
        )
        let snapshot = LanguageProfiles.resolve(
            profile: profile,
            globalDefaults: globals,
            credentialOverride: ""
        )
        TestSupport.expectEqual(snapshot.transcriptionBaseURL, "https://synthetic.example/profile-v1")
        TestSupport.expectEqual(snapshot.transcriptionAPIKey, globals.transcriptionAPIKey)
        TestSupport.expectEqual(snapshot.transcriptionModel, globals.transcriptionModel)
        TestSupport.expectEqual(snapshot.realtimeModel, "profile-realtime-model")
        TestSupport.expectEqual(snapshot.ordinaryCleanupSystemPrompt, "profile prompt")
    }

    private static func testResolutionUsesInjectedCredentialOverride() {
        let profileID = UUID()
        let profile = LanguageProfile(
            id: profileID,
            name: "Profile",
            inputLanguageCode: "en",
            transcriptionURLOverride: "",
            transcriptionModelOverride: "",
            realtimeModelOverride: "",
            postProcessingPromptOverride: ""
        )
        let globals = LanguageProfileGlobalDefaults(
            transcriptionBaseURL: "https://synthetic.example/v1",
            transcriptionAPIKey: "global-key",
            transcriptionModel: "whisper-large-v3",
            realtimeModel: "whisper-large-v3",
            customSystemPrompt: ""
        )
        let store = InMemoryCredentialStore()

        let inherited = LanguageProfiles.resolve(
            profile: profile,
            globalDefaults: globals,
            credentialOverride: store.loadAPIKeyOverride(profileID: profileID) ?? ""
        )
        TestSupport.expectEqual(inherited.transcriptionAPIKey, "global-key")

        store.setAPIKeyOverride("  profile-key  ", profileID: profileID)
        let overridden = LanguageProfiles.resolve(
            profile: profile,
            globalDefaults: globals,
            credentialOverride: store.loadAPIKeyOverride(profileID: profileID) ?? ""
        )
        TestSupport.expectEqual(overridden.transcriptionAPIKey, "profile-key")

        store.clearAPIKeyOverride(profileID: profileID)
        let emptyOverride = LanguageProfiles.resolve(
            profile: profile,
            globalDefaults: globals,
            credentialOverride: store.loadAPIKeyOverride(profileID: profileID) ?? ""
        )
        TestSupport.expectEqual(emptyOverride.transcriptionAPIKey, "global-key")
    }

    private static func testResolutionAutoDetectHasNilLanguageHint() {
        let globals = LanguageProfileGlobalDefaults(
            transcriptionBaseURL: "",
            transcriptionAPIKey: "",
            transcriptionModel: "",
            realtimeModel: "",
            customSystemPrompt: ""
        )
        let autoDetect = LanguageProfile(
            id: UUID(),
            name: "Auto",
            inputLanguageCode: "",
            transcriptionURLOverride: "",
            transcriptionModelOverride: "",
            realtimeModelOverride: "",
            postProcessingPromptOverride: ""
        )
        let autoSnapshot = LanguageProfiles.resolve(
            profile: autoDetect,
            globalDefaults: globals,
            credentialOverride: ""
        )
        TestSupport.expectEqual(autoSnapshot.languageHint, nil)
        TestSupport.expectEqual(autoSnapshot.inputLanguageCode, "")

        let english = LanguageProfile(
            id: UUID(),
            name: "English",
            inputLanguageCode: "EN",
            transcriptionURLOverride: "",
            transcriptionModelOverride: "",
            realtimeModelOverride: "",
            postProcessingPromptOverride: ""
        )
        let englishSnapshot = LanguageProfiles.resolve(
            profile: english,
            globalDefaults: globals,
            credentialOverride: ""
        )
        TestSupport.expectEqual(englishSnapshot.languageHint, "en")
        TestSupport.expectEqual(englishSnapshot.inputLanguageCode, "en")
    }

    // MARK: - Prompt scope

    private static func testPromptScopeHonorsProfileOverrideOnlyForOrdinary() {
        let profile = LanguageProfile(
            id: UUID(),
            name: "Profile",
            inputLanguageCode: "en",
            transcriptionURLOverride: "",
            transcriptionModelOverride: "",
            realtimeModelOverride: "",
            postProcessingPromptOverride: "profile-specific prompt"
        )
        let globals = LanguageProfileGlobalDefaults(
            transcriptionBaseURL: "",
            transcriptionAPIKey: "",
            transcriptionModel: "",
            realtimeModel: "",
            customSystemPrompt: "global prompt"
        )
        let snapshot = LanguageProfiles.resolve(
            profile: profile,
            globalDefaults: globals,
            credentialOverride: ""
        )
        TestSupport.expectEqual(
            LanguageProfiles.customSystemPrompt(for: .ordinaryDictation, resolvedProfile: snapshot),
            "profile-specific prompt"
        )
        TestSupport.expectEqual(
            LanguageProfiles.customSystemPrompt(for: .editModeCommandTransform, resolvedProfile: snapshot),
            ""
        )
    }

    private static func testPromptScopeFallsBackToGlobalCustomPrompt() {
        let profile = LanguageProfile(
            id: UUID(),
            name: "Profile",
            inputLanguageCode: "en",
            transcriptionURLOverride: "",
            transcriptionModelOverride: "",
            realtimeModelOverride: "",
            postProcessingPromptOverride: ""
        )
        let globals = LanguageProfileGlobalDefaults(
            transcriptionBaseURL: "",
            transcriptionAPIKey: "",
            transcriptionModel: "",
            realtimeModel: "",
            customSystemPrompt: "global prompt"
        )
        let snapshot = LanguageProfiles.resolve(
            profile: profile,
            globalDefaults: globals,
            credentialOverride: ""
        )
        TestSupport.expectEqual(
            LanguageProfiles.customSystemPrompt(for: .ordinaryDictation, resolvedProfile: snapshot),
            "global prompt"
        )
        TestSupport.expectEqual(
            LanguageProfiles.customSystemPrompt(for: .editModeCommandTransform, resolvedProfile: snapshot),
            ""
        )
    }

    // MARK: - Translation independence

    private static func testTranslationIndependence() {
        let globals = LanguageProfileGlobalDefaults(
            transcriptionBaseURL: "https://synthetic.example/v1",
            transcriptionAPIKey: "synthetic-key",
            transcriptionModel: "whisper-large-v3",
            realtimeModel: "whisper-large-v3",
            customSystemPrompt: "global prompt"
        )
        let englishProfile = LanguageProfile(
            id: UUID(),
            name: "English",
            inputLanguageCode: "en",
            transcriptionURLOverride: "",
            transcriptionModelOverride: "",
            realtimeModelOverride: "",
            postProcessingPromptOverride: ""
        )
        let danishProfile = LanguageProfile(
            id: UUID(),
            name: "Danish",
            inputLanguageCode: "da",
            transcriptionURLOverride: "",
            transcriptionModelOverride: "",
            realtimeModelOverride: "",
            postProcessingPromptOverride: ""
        )
        let autoDetectProfile = LanguageProfile(
            id: UUID(),
            name: "Auto",
            inputLanguageCode: "",
            transcriptionURLOverride: "",
            transcriptionModelOverride: "",
            realtimeModelOverride: "",
            postProcessingPromptOverride: ""
        )

        let credentials = InMemoryCredentialStore()
        let englishSnapshot = LanguageProfileCatalog(
            profiles: [englishProfile],
            activeProfileID: englishProfile.id
        ).resolvedActiveProfile(globalDefaults: globals, credentials: credentials)
        let danishSnapshot = LanguageProfileCatalog(
            profiles: [danishProfile],
            activeProfileID: danishProfile.id
        ).resolvedActiveProfile(globalDefaults: globals, credentials: credentials)
        let autoSnapshot = LanguageProfileCatalog(
            profiles: [autoDetectProfile],
            activeProfileID: autoDetectProfile.id
        ).resolvedActiveProfile(globalDefaults: globals, credentials: credentials)

        // The only fields that should differ across input languages are
        // inputLanguageCode and languageHint; everything else must match.
        TestSupport.expectEqual(englishSnapshot.transcriptionBaseURL, danishSnapshot.transcriptionBaseURL)
        TestSupport.expectEqual(englishSnapshot.transcriptionBaseURL, autoSnapshot.transcriptionBaseURL)
        TestSupport.expectEqual(englishSnapshot.transcriptionAPIKey, danishSnapshot.transcriptionAPIKey)
        TestSupport.expectEqual(englishSnapshot.transcriptionAPIKey, autoSnapshot.transcriptionAPIKey)
        TestSupport.expectEqual(englishSnapshot.transcriptionModel, danishSnapshot.transcriptionModel)
        TestSupport.expectEqual(englishSnapshot.transcriptionModel, autoSnapshot.transcriptionModel)
        TestSupport.expectEqual(englishSnapshot.realtimeModel, danishSnapshot.realtimeModel)
        TestSupport.expectEqual(englishSnapshot.realtimeModel, autoSnapshot.realtimeModel)
        TestSupport.expectEqual(englishSnapshot.ordinaryCleanupSystemPrompt, danishSnapshot.ordinaryCleanupSystemPrompt)
        TestSupport.expectEqual(englishSnapshot.ordinaryCleanupSystemPrompt, autoSnapshot.ordinaryCleanupSystemPrompt)

        TestSupport.expectEqual(englishSnapshot.inputLanguageCode, "en")
        TestSupport.expectEqual(danishSnapshot.inputLanguageCode, "da")
        TestSupport.expectEqual(autoSnapshot.inputLanguageCode, "")
        TestSupport.expectEqual(englishSnapshot.languageHint, "en")
        TestSupport.expectEqual(danishSnapshot.languageHint, "da")
        TestSupport.expectEqual(autoSnapshot.languageHint, nil)

        // ResolvedLanguageProfile has no Output Language field, confirming
        // translation stays independent of the active profile. The
        // property assertions above already exercise the documented
        // fields, so there is no additional runtime check needed here.
    }

    // MARK: - Snapshot immutability

    private static func testSnapshotImmutability() {
        let profileID = UUID()
        var profile = LanguageProfile(
            id: profileID,
            name: "Profile",
            inputLanguageCode: "en",
            transcriptionURLOverride: "https://synthetic.example/profile-v1",
            transcriptionModelOverride: "profile-model",
            realtimeModelOverride: "profile-realtime",
            postProcessingPromptOverride: "profile prompt"
        )
        var globals = LanguageProfileGlobalDefaults(
            transcriptionBaseURL: "https://synthetic.example/global-v1",
            transcriptionAPIKey: "global-key",
            transcriptionModel: "global-model",
            realtimeModel: "global-realtime",
            customSystemPrompt: "global prompt"
        )
        let store = InMemoryCredentialStore(values: [profileID: "profile-key"])

        let snapshot = LanguageProfiles.resolve(
            profile: profile,
            globalDefaults: globals,
            credentialOverride: store.loadAPIKeyOverride(profileID: profileID) ?? ""
        )
        let frozen = (
            profileID: snapshot.profileID,
            profileName: snapshot.profileName,
            inputLanguageCode: snapshot.inputLanguageCode,
            languageHint: snapshot.languageHint,
            transcriptionBaseURL: snapshot.transcriptionBaseURL,
            transcriptionAPIKey: snapshot.transcriptionAPIKey,
            transcriptionModel: snapshot.transcriptionModel,
            realtimeModel: snapshot.realtimeModel,
            ordinaryCleanupSystemPrompt: snapshot.ordinaryCleanupSystemPrompt
        )

        // Mutate every input that could plausibly change mid-attempt.
        profile.transcriptionURLOverride = "https://synthetic.example/profile-v2"
        profile.transcriptionModelOverride = ""
        profile.realtimeModelOverride = "profile-realtime-2"
        profile.postProcessingPromptOverride = "  "
        profile.inputLanguageCode = "da"
        globals.transcriptionBaseURL = "https://synthetic.example/global-v2"
        globals.transcriptionAPIKey = "global-key-2"
        globals.transcriptionModel = "global-model-2"
        globals.realtimeModel = "global-realtime-2"
        globals.customSystemPrompt = ""
        store.setAPIKeyOverride("profile-key-2", profileID: profileID)

        // ResolvedLanguageProfile stores String/UUID/String? — all value
        // types — so every field on `snapshot` is a copy of the original
        // input at the time of resolution. Re-reading them here MUST
        // match the originally captured tuple field-by-field.
        TestSupport.expectEqual(snapshot.profileID, frozen.profileID)
        TestSupport.expectEqual(snapshot.profileName, frozen.profileName)
        TestSupport.expectEqual(snapshot.inputLanguageCode, frozen.inputLanguageCode)
        TestSupport.expectEqual(snapshot.languageHint, frozen.languageHint)
        TestSupport.expectEqual(snapshot.transcriptionBaseURL, frozen.transcriptionBaseURL)
        TestSupport.expectEqual(snapshot.transcriptionAPIKey, frozen.transcriptionAPIKey)
        TestSupport.expectEqual(snapshot.transcriptionModel, frozen.transcriptionModel)
        TestSupport.expectEqual(snapshot.realtimeModel, frozen.realtimeModel)
        TestSupport.expectEqual(snapshot.ordinaryCleanupSystemPrompt, frozen.ordinaryCleanupSystemPrompt)
    }

    // MARK: - Add profile

    private static func testAddProfileSuccessAndBecomesActive() {
        let englishID = UUID()
        let catalog = LanguageProfileCatalog(
            profiles: [
                LanguageProfile(
                    id: englishID,
                    name: "English",
                    inputLanguageCode: "en",
                    transcriptionURLOverride: "",
                    transcriptionModelOverride: "",
                    realtimeModelOverride: "",
                    postProcessingPromptOverride: ""
                )
            ],
            activeProfileID: englishID
        )
        switch LanguageProfiles.addProfile(
            name: "  Danish  ",
            inputLanguageCode: "da",
            to: catalog
        ) {
        case .success(let payload):
            TestSupport.expectEqual(payload.catalog.profiles.count, 2)
            TestSupport.expectEqual(payload.catalog.profiles.last?.name, "Danish")
            TestSupport.expectEqual(payload.catalog.profiles.last?.inputLanguageCode, "da")
            TestSupport.expectEqual(payload.catalog.activeProfileID, payload.profile.id)
            TestSupport.expectEqual(payload.profile.transcriptionURLOverride, "")
            TestSupport.expectEqual(payload.profile.transcriptionModelOverride, "")
            TestSupport.expectEqual(payload.profile.realtimeModelOverride, "")
            TestSupport.expectEqual(payload.profile.postProcessingPromptOverride, "")
        case .failure(let error):
            fatalError("Expected add success, got \(error.message)")
        }
    }

    private static func testAddProfileRejectsEmptyName() {
        let catalog = LanguageProfileCatalog(
            profiles: [
                LanguageProfile(
                    id: UUID(),
                    name: "English",
                    inputLanguageCode: "en",
                    transcriptionURLOverride: "",
                    transcriptionModelOverride: "",
                    realtimeModelOverride: "",
                    postProcessingPromptOverride: ""
                )
            ],
            activeProfileID: UUID()
        )
        switch LanguageProfiles.addProfile(name: "   ", inputLanguageCode: "da", to: catalog) {
        case .success:
            fatalError("Expected empty-name rejection")
        case .failure(.emptyName):
            break
        case .failure(let other):
            fatalError("Expected .emptyName, got \(other)")
        }
    }

    private static func testAddProfileRejectsUnsupportedCode() {
        let catalog = LanguageProfileCatalog(
            profiles: [
                LanguageProfile(
                    id: UUID(),
                    name: "English",
                    inputLanguageCode: "en",
                    transcriptionURLOverride: "",
                    transcriptionModelOverride: "",
                    realtimeModelOverride: "",
                    postProcessingPromptOverride: ""
                )
            ],
            activeProfileID: UUID()
        )
        switch LanguageProfiles.addProfile(name: "Klingon", inputLanguageCode: "tlh", to: catalog) {
        case .success:
            fatalError("Expected unsupported-code rejection")
        case .failure(.unsupportedLanguageCode):
            break
        case .failure(let other):
            fatalError("Expected .unsupportedLanguageCode, got \(other)")
        }
    }

    private static func testAddProfileRejectsDuplicateName() {
        let catalog = LanguageProfileCatalog(
            profiles: [
                LanguageProfile(
                    id: UUID(),
                    name: "English",
                    inputLanguageCode: "en",
                    transcriptionURLOverride: "",
                    transcriptionModelOverride: "",
                    realtimeModelOverride: "",
                    postProcessingPromptOverride: ""
                )
            ],
            activeProfileID: UUID()
        )
        switch LanguageProfiles.addProfile(name: "english", inputLanguageCode: "da", to: catalog) {
        case .success:
            fatalError("Expected duplicate-name rejection")
        case .failure(.duplicateName):
            break
        case .failure(let other):
            fatalError("Expected .duplicateName, got \(other)")
        }
    }

    private static func testAddProfileRejectsDuplicateLanguageCode() {
        let catalog = LanguageProfileCatalog(
            profiles: [
                LanguageProfile(
                    id: UUID(),
                    name: "English",
                    inputLanguageCode: "en",
                    transcriptionURLOverride: "",
                    transcriptionModelOverride: "",
                    realtimeModelOverride: "",
                    postProcessingPromptOverride: ""
                )
            ],
            activeProfileID: UUID()
        )
        switch LanguageProfiles.addProfile(name: "British", inputLanguageCode: "en", to: catalog) {
        case .success:
            fatalError("Expected duplicate-code rejection")
        case .failure(.duplicateLanguageCode):
            break
        case .failure(let other):
            fatalError("Expected .duplicateLanguageCode, got \(other)")
        }
    }

    private static func testAddProfileRejectsSecondAutoDetect() {
        let catalog = LanguageProfileCatalog(
            profiles: [
                LanguageProfile(
                    id: UUID(),
                    name: "Auto",
                    inputLanguageCode: "",
                    transcriptionURLOverride: "",
                    transcriptionModelOverride: "",
                    realtimeModelOverride: "",
                    postProcessingPromptOverride: ""
                )
            ],
            activeProfileID: UUID()
        )
        switch LanguageProfiles.addProfile(name: "Auto Too", inputLanguageCode: "", to: catalog) {
        case .success:
            fatalError("Expected second Auto-detect rejection")
        case .failure(.duplicateLanguageCode):
            break
        case .failure(let other):
            fatalError("Expected .duplicateLanguageCode, got \(other)")
        }
    }

    private static func testAddProfileDanishCodePath() {
        // Danish is the explicit per-story language code in the
        // specification. Pin the supported-language entry so a future
        // accidental rename or removal of Danish fails fast.
        let danish = LanguageProfiles.supportedInputLanguages.first(where: { $0.code == "da" })
        TestSupport.expectEqual(danish?.name, "Danish")
        let catalog = LanguageProfileCatalog(
            profiles: [
                LanguageProfile(
                    id: UUID(),
                    name: "English",
                    inputLanguageCode: "en",
                    transcriptionURLOverride: "",
                    transcriptionModelOverride: "",
                    realtimeModelOverride: "",
                    postProcessingPromptOverride: ""
                )
            ],
            activeProfileID: UUID()
        )
        switch LanguageProfiles.addProfile(name: "Danish", inputLanguageCode: "da", to: catalog) {
        case .success(let payload):
            TestSupport.expectEqual(payload.profile.inputLanguageCode, "da")
        case .failure(let error):
            fatalError("Expected Danish add success, got \(error.message)")
        }
    }

    // MARK: - Rename profile

    private static func testRenameProfileSuccessAndTrims() {
        let id = UUID()
        let catalog = LanguageProfileCatalog(
            profiles: [
                LanguageProfile(
                    id: id,
                    name: "English",
                    inputLanguageCode: "en",
                    transcriptionURLOverride: "",
                    transcriptionModelOverride: "",
                    realtimeModelOverride: "",
                    postProcessingPromptOverride: ""
                )
            ],
            activeProfileID: id
        )
        switch LanguageProfiles.renameProfile(in: catalog, id: id, newName: "  American English  ") {
        case .success(let newCatalog):
            TestSupport.expectEqual(newCatalog.profiles[0].name, "American English")
            TestSupport.expectEqual(newCatalog.activeProfileID, id)
        case .failure(let error):
            fatalError("Expected rename success, got \(error.message)")
        }
    }

    private static func testRenameProfileRejectsEmptyName() {
        let id = UUID()
        let catalog = LanguageProfileCatalog(
            profiles: [
                LanguageProfile(
                    id: id,
                    name: "English",
                    inputLanguageCode: "en",
                    transcriptionURLOverride: "",
                    transcriptionModelOverride: "",
                    realtimeModelOverride: "",
                    postProcessingPromptOverride: ""
                )
            ],
            activeProfileID: id
        )
        switch LanguageProfiles.renameProfile(in: catalog, id: id, newName: "   ") {
        case .success:
            fatalError("Expected empty-name rejection")
        case .failure(.emptyName):
            break
        case .failure(let other):
            fatalError("Expected .emptyName, got \(other)")
        }
    }

    private static func testRenameProfileRejectsDuplicateName() {
        let firstID = UUID()
        let secondID = UUID()
        let catalog = LanguageProfileCatalog(
            profiles: [
                LanguageProfile(
                    id: firstID,
                    name: "English",
                    inputLanguageCode: "en",
                    transcriptionURLOverride: "",
                    transcriptionModelOverride: "",
                    realtimeModelOverride: "",
                    postProcessingPromptOverride: ""
                ),
                LanguageProfile(
                    id: secondID,
                    name: "Danish",
                    inputLanguageCode: "da",
                    transcriptionURLOverride: "",
                    transcriptionModelOverride: "",
                    realtimeModelOverride: "",
                    postProcessingPromptOverride: ""
                )
            ],
            activeProfileID: firstID
        )
        switch LanguageProfiles.renameProfile(in: catalog, id: secondID, newName: "ENGLISH") {
        case .success:
            fatalError("Expected duplicate-name rejection")
        case .failure(.duplicateName):
            break
        case .failure(let other):
            fatalError("Expected .duplicateName, got \(other)")
        }
    }

    private static func testRenameProfileRejectsUnknownID() {
        let id = UUID()
        let catalog = LanguageProfileCatalog(
            profiles: [
                LanguageProfile(
                    id: id,
                    name: "English",
                    inputLanguageCode: "en",
                    transcriptionURLOverride: "",
                    transcriptionModelOverride: "",
                    realtimeModelOverride: "",
                    postProcessingPromptOverride: ""
                )
            ],
            activeProfileID: id
        )
        let bogus = UUID()
        switch LanguageProfiles.renameProfile(in: catalog, id: bogus, newName: "X") {
        case .success:
            fatalError("Expected unknown-ID rejection")
        case .failure(.unknownProfileID(let returned)):
            TestSupport.expectEqual(returned, bogus)
        case .failure(let other):
            fatalError("Expected .unknownProfileID, got \(other)")
        }
    }

    private static func testRenameProfileSameNameIsNoOp() {
        let id = UUID()
        let catalog = LanguageProfileCatalog(
            profiles: [
                LanguageProfile(
                    id: id,
                    name: "English",
                    inputLanguageCode: "en",
                    transcriptionURLOverride: "",
                    transcriptionModelOverride: "",
                    realtimeModelOverride: "",
                    postProcessingPromptOverride: ""
                )
            ],
            activeProfileID: id
        )
        switch LanguageProfiles.renameProfile(in: catalog, id: id, newName: "English") {
        case .success(let newCatalog):
            TestSupport.expectEqual(newCatalog, catalog)
        case .failure(let error):
            fatalError("Expected no-op rename success, got \(error.message)")
        }
    }

    // MARK: - Reorder profile

    private static func testReorderProfileMovesUpAndDown() {
        let firstID = UUID()
        let secondID = UUID()
        let thirdID = UUID()
        let catalog = LanguageProfileCatalog(
            profiles: [
                LanguageProfile(id: firstID, name: "A", inputLanguageCode: "en", transcriptionURLOverride: "", transcriptionModelOverride: "", realtimeModelOverride: "", postProcessingPromptOverride: ""),
                LanguageProfile(id: secondID, name: "B", inputLanguageCode: "da", transcriptionURLOverride: "", transcriptionModelOverride: "", realtimeModelOverride: "", postProcessingPromptOverride: ""),
                LanguageProfile(id: thirdID, name: "C", inputLanguageCode: "fr", transcriptionURLOverride: "", transcriptionModelOverride: "", realtimeModelOverride: "", postProcessingPromptOverride: "")
            ],
            activeProfileID: firstID
        )

        // Move the third profile up by one (C → index 1).
        let upOne = LanguageProfiles.reorderProfile(in: catalog, id: thirdID, direction: .up)
        switch upOne {
        case .success(let newCatalog):
            TestSupport.expectEqual(newCatalog.profiles.map(\.id), [firstID, thirdID, secondID])
        case .failure(let error):
            fatalError("Expected up reorder success, got \(error.message)")
        }

        // Move the third profile (now at index 1) down by one (back to index 2).
        let intermediate = try! upOne.get()
        let downOne = LanguageProfiles.reorderProfile(in: intermediate, id: thirdID, direction: .down)
        switch downOne {
        case .success(let newCatalog):
            TestSupport.expectEqual(newCatalog.profiles.map(\.id), [firstID, secondID, thirdID])
        case .failure(let error):
            fatalError("Expected down reorder success, got \(error.message)")
        }
    }

    private static func testReorderProfileRejectsTopUp() {
        let id = UUID()
        let catalog = LanguageProfileCatalog(
            profiles: [
                LanguageProfile(id: id, name: "A", inputLanguageCode: "en", transcriptionURLOverride: "", transcriptionModelOverride: "", realtimeModelOverride: "", postProcessingPromptOverride: "")
            ],
            activeProfileID: id
        )
        switch LanguageProfiles.reorderProfile(in: catalog, id: id, direction: .up) {
        case .success:
            fatalError("Expected top-up rejection")
        case .failure(.invalidReorderIndex):
            break
        case .failure(let other):
            fatalError("Expected .invalidReorderIndex, got \(other)")
        }
    }

    private static func testReorderProfileRejectsBottomDown() {
        let id = UUID()
        let catalog = LanguageProfileCatalog(
            profiles: [
                LanguageProfile(id: id, name: "A", inputLanguageCode: "en", transcriptionURLOverride: "", transcriptionModelOverride: "", realtimeModelOverride: "", postProcessingPromptOverride: "")
            ],
            activeProfileID: id
        )
        switch LanguageProfiles.reorderProfile(in: catalog, id: id, direction: .down) {
        case .success:
            fatalError("Expected bottom-down rejection")
        case .failure(.invalidReorderIndex):
            break
        case .failure(let other):
            fatalError("Expected .invalidReorderIndex, got \(other)")
        }
    }

    private static func testReorderProfileRejectsUnknownID() {
        let id = UUID()
        let catalog = LanguageProfileCatalog(
            profiles: [
                LanguageProfile(id: id, name: "A", inputLanguageCode: "en", transcriptionURLOverride: "", transcriptionModelOverride: "", realtimeModelOverride: "", postProcessingPromptOverride: "")
            ],
            activeProfileID: id
        )
        switch LanguageProfiles.reorderProfile(in: catalog, id: UUID(), direction: .up) {
        case .success:
            fatalError("Expected unknown-ID rejection")
        case .failure(.unknownProfileID):
            break
        case .failure(let other):
            fatalError("Expected .unknownProfileID, got \(other)")
        }
    }

    // MARK: - Cycle active profile

    private static func testCycleActiveProfileAdvancesToNextInOrder() {
        let firstID = UUID()
        let secondID = UUID()
        let thirdID = UUID()
        let catalog = LanguageProfileCatalog(
            profiles: [
                LanguageProfile(id: firstID, name: "A", inputLanguageCode: "en", transcriptionURLOverride: "", transcriptionModelOverride: "", realtimeModelOverride: "", postProcessingPromptOverride: ""),
                LanguageProfile(id: secondID, name: "B", inputLanguageCode: "da", transcriptionURLOverride: "", transcriptionModelOverride: "", realtimeModelOverride: "", postProcessingPromptOverride: ""),
                LanguageProfile(id: thirdID, name: "C", inputLanguageCode: "fr", transcriptionURLOverride: "", transcriptionModelOverride: "", realtimeModelOverride: "", postProcessingPromptOverride: "")
            ],
            activeProfileID: firstID
        )

        let advanceToSecond = LanguageProfiles.cycleActiveProfile(in: catalog)
        TestSupport.expectEqual(advanceToSecond.catalog.activeProfileID, secondID)
        TestSupport.expectEqual(advanceToSecond.profile.id, secondID)
        // Profile order itself must be untouched by cycling.
        TestSupport.expectEqual(advanceToSecond.catalog.profiles.map(\.id), [firstID, secondID, thirdID])

        let advanceToThird = LanguageProfiles.cycleActiveProfile(in: advanceToSecond.catalog)
        TestSupport.expectEqual(advanceToThird.catalog.activeProfileID, thirdID)
        TestSupport.expectEqual(advanceToThird.profile.id, thirdID)
    }

    private static func testCycleActiveProfileWrapsAtEnd() {
        let firstID = UUID()
        let secondID = UUID()
        let catalog = LanguageProfileCatalog(
            profiles: [
                LanguageProfile(id: firstID, name: "A", inputLanguageCode: "en", transcriptionURLOverride: "", transcriptionModelOverride: "", realtimeModelOverride: "", postProcessingPromptOverride: ""),
                LanguageProfile(id: secondID, name: "B", inputLanguageCode: "da", transcriptionURLOverride: "", transcriptionModelOverride: "", realtimeModelOverride: "", postProcessingPromptOverride: "")
            ],
            activeProfileID: secondID
        )

        let wrapped = LanguageProfiles.cycleActiveProfile(in: catalog)
        TestSupport.expectEqual(wrapped.catalog.activeProfileID, firstID)
        TestSupport.expectEqual(wrapped.profile.id, firstID)
    }

    private static func testCycleActiveProfileSingleProfileIsNoOpButReportsProfile() {
        let onlyID = UUID()
        let catalog = LanguageProfileCatalog(
            profiles: [
                LanguageProfile(id: onlyID, name: "Solo", inputLanguageCode: "en", transcriptionURLOverride: "", transcriptionModelOverride: "", realtimeModelOverride: "", postProcessingPromptOverride: "")
            ],
            activeProfileID: onlyID
        )

        let result = LanguageProfiles.cycleActiveProfile(in: catalog)
        TestSupport.expectEqual(result.catalog, catalog)
        TestSupport.expectEqual(result.profile.id, onlyID)
        TestSupport.expectEqual(result.profile.name, "Solo")
    }

    /// The Switch Language shortcut trigger must be rejected — no
    /// cycling, no persistence, no overlay — whenever a Processing
    /// Attempt is in flight (recording, transcribing, or both). This is
    /// the pure predicate `AppState.handleSwitchLanguageShortcutTriggered`
    /// delegates to instead of inlining the busy check, so it is
    /// deterministically testable outside the AppKit-dependent host.
    private static func testShouldRejectSwitchLanguageTriggerBusyRejection() {
        TestSupport.expect(
            !LanguageProfiles.shouldRejectSwitchLanguageTrigger(isRecording: false, isTranscribing: false),
            "Idle (not recording, not transcribing) must not reject the trigger"
        )
        TestSupport.expect(
            LanguageProfiles.shouldRejectSwitchLanguageTrigger(isRecording: true, isTranscribing: false),
            "Recording must reject the trigger"
        )
        TestSupport.expect(
            LanguageProfiles.shouldRejectSwitchLanguageTrigger(isRecording: false, isTranscribing: true),
            "Transcribing must reject the trigger"
        )
        TestSupport.expect(
            LanguageProfiles.shouldRejectSwitchLanguageTrigger(isRecording: true, isTranscribing: true),
            "Recording and transcribing simultaneously must reject the trigger"
        )
    }

    // MARK: - Delete profile

    private static func testDeleteProfileRejectsFinalProfile() {
        let id = UUID()
        let catalog = LanguageProfileCatalog(
            profiles: [
                LanguageProfile(id: id, name: "A", inputLanguageCode: "en", transcriptionURLOverride: "", transcriptionModelOverride: "", realtimeModelOverride: "", postProcessingPromptOverride: "")
            ],
            activeProfileID: id
        )
        let store = InMemoryCredentialStore()
        switch LanguageProfiles.deleteProfile(from: catalog, id: id, credentials: store) {
        case .success:
            fatalError("Expected final-profile rejection")
        case .failure(.cannotDeleteFinalProfile):
            break
        case .failure(let other):
            fatalError("Expected .cannotDeleteFinalProfile, got \(other)")
        }
    }

    private static func testDeleteProfileRejectsUnknownID() {
        let id = UUID()
        let catalog = LanguageProfileCatalog(
            profiles: [
                LanguageProfile(id: id, name: "A", inputLanguageCode: "en", transcriptionURLOverride: "", transcriptionModelOverride: "", realtimeModelOverride: "", postProcessingPromptOverride: "")
            ],
            activeProfileID: id
        )
        let store = InMemoryCredentialStore()
        switch LanguageProfiles.deleteProfile(from: catalog, id: UUID(), credentials: store) {
        case .success:
            fatalError("Expected unknown-ID rejection")
        case .failure(.unknownProfileID):
            break
        case .failure(let other):
            fatalError("Expected .unknownProfileID, got \(other)")
        }
    }

    private static func testDeleteProfileRemovesCredentialOverride() {
        let firstID = UUID()
        let secondID = UUID()
        let catalog = LanguageProfileCatalog(
            profiles: [
                LanguageProfile(id: firstID, name: "English", inputLanguageCode: "en", transcriptionURLOverride: "", transcriptionModelOverride: "", realtimeModelOverride: "", postProcessingPromptOverride: ""),
                LanguageProfile(id: secondID, name: "Danish", inputLanguageCode: "da", transcriptionURLOverride: "", transcriptionModelOverride: "", realtimeModelOverride: "", postProcessingPromptOverride: "")
            ],
            activeProfileID: firstID
        )
        let store = InMemoryCredentialStore(values: [firstID: "synthetic-first-key", secondID: "synthetic-second-key"])
        switch LanguageProfiles.deleteProfile(from: catalog, id: firstID, credentials: store) {
        case .success:
            break
        case .failure(let error):
            fatalError("Expected delete success, got \(error.message)")
        }
        TestSupport.expect(
            store.loadAPIKeyOverride(profileID: firstID) == nil,
            "Deleted profile's credential override must be removed from the store"
        )
        TestSupport.expect(
            store.loadAPIKeyOverride(profileID: secondID) == "synthetic-second-key",
            "Surviving profile's credential override must remain untouched"
        )
    }

    private static func testDeleteActiveProfileSelectsSuccessorInOrder() {
        let firstID = UUID()
        let secondID = UUID()
        let thirdID = UUID()
        let catalog = LanguageProfileCatalog(
            profiles: [
                LanguageProfile(id: firstID, name: "English", inputLanguageCode: "en", transcriptionURLOverride: "", transcriptionModelOverride: "", realtimeModelOverride: "", postProcessingPromptOverride: ""),
                LanguageProfile(id: secondID, name: "Danish", inputLanguageCode: "da", transcriptionURLOverride: "", transcriptionModelOverride: "", realtimeModelOverride: "", postProcessingPromptOverride: ""),
                LanguageProfile(id: thirdID, name: "French", inputLanguageCode: "fr", transcriptionURLOverride: "", transcriptionModelOverride: "", realtimeModelOverride: "", postProcessingPromptOverride: "")
            ],
            activeProfileID: firstID
        )
        let store = InMemoryCredentialStore()
        // Deleting the active (first) profile must select the successor
        // in configured order — the profile that followed it, i.e. Danish.
        switch LanguageProfiles.deleteProfile(from: catalog, id: firstID, credentials: store) {
        case .success(let newCatalog):
            TestSupport.expectEqual(newCatalog.activeProfileID, secondID)
            TestSupport.expectEqual(newCatalog.profiles.map(\.id), [secondID, thirdID])
        case .failure(let error):
            fatalError("Expected delete success, got \(error.message)")
        }
    }

    private static func testDeleteLastProfileSelectsLastRemaining() {
        let firstID = UUID()
        let secondID = UUID()
        let catalog = LanguageProfileCatalog(
            profiles: [
                LanguageProfile(id: firstID, name: "English", inputLanguageCode: "en", transcriptionURLOverride: "", transcriptionModelOverride: "", realtimeModelOverride: "", postProcessingPromptOverride: ""),
                LanguageProfile(id: secondID, name: "Danish", inputLanguageCode: "da", transcriptionURLOverride: "", transcriptionModelOverride: "", realtimeModelOverride: "", postProcessingPromptOverride: "")
            ],
            activeProfileID: secondID
        )
        let store = InMemoryCredentialStore()
        // Deleting the last profile (Danish, which is active) must
        // select the last remaining profile — English.
        switch LanguageProfiles.deleteProfile(from: catalog, id: secondID, credentials: store) {
        case .success(let newCatalog):
            TestSupport.expectEqual(newCatalog.activeProfileID, firstID)
            TestSupport.expectEqual(newCatalog.profiles.map(\.id), [firstID])
        case .failure(let error):
            fatalError("Expected delete success, got \(error.message)")
        }
    }

    // MARK: - Select profile

    private static func testSelectProfileSuccess() {
        let firstID = UUID()
        let secondID = UUID()
        let catalog = LanguageProfileCatalog(
            profiles: [
                LanguageProfile(id: firstID, name: "English", inputLanguageCode: "en", transcriptionURLOverride: "", transcriptionModelOverride: "", realtimeModelOverride: "", postProcessingPromptOverride: ""),
                LanguageProfile(id: secondID, name: "Danish", inputLanguageCode: "da", transcriptionURLOverride: "", transcriptionModelOverride: "", realtimeModelOverride: "", postProcessingPromptOverride: "")
            ],
            activeProfileID: firstID
        )
        switch LanguageProfiles.selectProfile(in: catalog, id: secondID) {
        case .success(let newCatalog):
            TestSupport.expectEqual(newCatalog.activeProfileID, secondID)
            TestSupport.expectEqual(newCatalog.profiles, catalog.profiles)
        case .failure(let error):
            fatalError("Expected select success, got \(error.message)")
        }
    }

    private static func testSelectProfileRejectsUnknownID() {
        let id = UUID()
        let catalog = LanguageProfileCatalog(
            profiles: [
                LanguageProfile(id: id, name: "English", inputLanguageCode: "en", transcriptionURLOverride: "", transcriptionModelOverride: "", realtimeModelOverride: "", postProcessingPromptOverride: "")
            ],
            activeProfileID: id
        )
        switch LanguageProfiles.selectProfile(in: catalog, id: UUID()) {
        case .success:
            fatalError("Expected unknown-ID rejection")
        case .failure(.unknownProfileID):
            break
        case .failure(let other):
            fatalError("Expected .unknownProfileID, got \(other)")
        }
    }

    // MARK: - Update profile overrides

    private static func testUpdateProfileOverridesTrimsAndPersists() {
        let id = UUID()
        let catalog = LanguageProfileCatalog(
            profiles: [
                LanguageProfile(id: id, name: "English", inputLanguageCode: "en", transcriptionURLOverride: "", transcriptionModelOverride: "", realtimeModelOverride: "", postProcessingPromptOverride: "")
            ],
            activeProfileID: id
        )
        let updated = LanguageProfile(
            id: id,
            name: "English",
            inputLanguageCode: "en",
            transcriptionURLOverride: "  https://synthetic.example/v1  ",
            transcriptionModelOverride: "  profile-model  ",
            realtimeModelOverride: "  profile-realtime  ",
            postProcessingPromptOverride: "  profile prompt  "
        )
        switch LanguageProfiles.updateProfile(in: catalog, with: updated) {
        case .success(let newCatalog):
            TestSupport.expectEqual(newCatalog.profiles[0].transcriptionURLOverride, "https://synthetic.example/v1")
            TestSupport.expectEqual(newCatalog.profiles[0].transcriptionModelOverride, "profile-model")
            TestSupport.expectEqual(newCatalog.profiles[0].realtimeModelOverride, "profile-realtime")
            TestSupport.expectEqual(newCatalog.profiles[0].postProcessingPromptOverride, "profile prompt")
        case .failure(let error):
            fatalError("Expected update success, got \(error.message)")
        }
    }

    private static func testUpdateProfileRejectsDuplicateName() {
        let firstID = UUID()
        let secondID = UUID()
        let catalog = LanguageProfileCatalog(
            profiles: [
                LanguageProfile(id: firstID, name: "English", inputLanguageCode: "en", transcriptionURLOverride: "", transcriptionModelOverride: "", realtimeModelOverride: "", postProcessingPromptOverride: ""),
                LanguageProfile(id: secondID, name: "Danish", inputLanguageCode: "da", transcriptionURLOverride: "", transcriptionModelOverride: "", realtimeModelOverride: "", postProcessingPromptOverride: "")
            ],
            activeProfileID: firstID
        )
        let updated = LanguageProfile(
            id: secondID,
            name: "english",
            inputLanguageCode: "da",
            transcriptionURLOverride: "",
            transcriptionModelOverride: "",
            realtimeModelOverride: "",
            postProcessingPromptOverride: ""
        )
        switch LanguageProfiles.updateProfile(in: catalog, with: updated) {
        case .success:
            fatalError("Expected duplicate-name rejection")
        case .failure(.duplicateName):
            break
        case .failure(let other):
            fatalError("Expected .duplicateName, got \(other)")
        }
    }

    private static func testUpdateProfileRejectsDuplicateLanguageCode() {
        let firstID = UUID()
        let secondID = UUID()
        let catalog = LanguageProfileCatalog(
            profiles: [
                LanguageProfile(id: firstID, name: "English", inputLanguageCode: "en", transcriptionURLOverride: "", transcriptionModelOverride: "", realtimeModelOverride: "", postProcessingPromptOverride: ""),
                LanguageProfile(id: secondID, name: "Danish", inputLanguageCode: "da", transcriptionURLOverride: "", transcriptionModelOverride: "", realtimeModelOverride: "", postProcessingPromptOverride: "")
            ],
            activeProfileID: firstID
        )
        let updated = LanguageProfile(
            id: secondID,
            name: "Renamed",
            inputLanguageCode: "en",
            transcriptionURLOverride: "",
            transcriptionModelOverride: "",
            realtimeModelOverride: "",
            postProcessingPromptOverride: ""
        )
        switch LanguageProfiles.updateProfile(in: catalog, with: updated) {
        case .success:
            fatalError("Expected duplicate-code rejection")
        case .failure(.duplicateLanguageCode):
            break
        case .failure(let other):
            fatalError("Expected .duplicateLanguageCode, got \(other)")
        }
    }

    // MARK: - Credential store mutations

    private static func testSetAPIKeyOverridePersistsThroughStore() {
        let profileID = UUID()
        let store = InMemoryCredentialStore()
        LanguageProfiles.setAPIKeyOverride(
            "  synthetic-key  ",
            for: profileID,
            credentials: store
        )
        TestSupport.expectEqual(
            store.loadAPIKeyOverride(profileID: profileID),
            "synthetic-key"
        )

        // An empty / whitespace submission must be a no-op, not a
        // clobber of the stored value — the UI uses Clear for that.
        LanguageProfiles.setAPIKeyOverride("   ", for: profileID, credentials: store)
        TestSupport.expectEqual(
            store.loadAPIKeyOverride(profileID: profileID),
            "synthetic-key"
        )
    }

    private static func testClearAPIKeyOverrideRemovesFromStore() {
        let profileID = UUID()
        let store = InMemoryCredentialStore(values: [profileID: "synthetic-key"])
        LanguageProfiles.clearAPIKeyOverride(for: profileID, credentials: store)
        TestSupport.expectEqual(
            store.loadAPIKeyOverride(profileID: profileID),
            nil
        )
    }

    // MARK: - Editor prompt helper

    private static func testEffectiveCleanupPromptUsesProfileOverride() {
        let profile = LanguageProfile(
            id: UUID(),
            name: "P",
            inputLanguageCode: "en",
            transcriptionURLOverride: "",
            transcriptionModelOverride: "",
            realtimeModelOverride: "",
            postProcessingPromptOverride: "  profile-specific  "
        )
        let globals = LanguageProfileGlobalDefaults(
            transcriptionBaseURL: "",
            transcriptionAPIKey: "",
            transcriptionModel: "",
            realtimeModel: "",
            customSystemPrompt: "global prompt"
        )
        TestSupport.expectEqual(
            LanguageProfiles.effectiveCleanupPrompt(
                profile: profile,
                globalDefaults: globals,
                builtInDefaultPrompt: "BUILTIN"
            ),
            "profile-specific"
        )
    }

    private static func testEffectiveCleanupPromptFallsBackToGlobal() {
        let profile = LanguageProfile(
            id: UUID(),
            name: "P",
            inputLanguageCode: "en",
            transcriptionURLOverride: "",
            transcriptionModelOverride: "",
            realtimeModelOverride: "",
            postProcessingPromptOverride: ""
        )
        let globals = LanguageProfileGlobalDefaults(
            transcriptionBaseURL: "",
            transcriptionAPIKey: "",
            transcriptionModel: "",
            realtimeModel: "",
            customSystemPrompt: "global prompt"
        )
        TestSupport.expectEqual(
            LanguageProfiles.effectiveCleanupPrompt(
                profile: profile,
                globalDefaults: globals,
                builtInDefaultPrompt: "BUILTIN"
            ),
            "global prompt"
        )
    }

    private static func testEffectiveCleanupPromptFallsBackToBuiltIn() {
        let profile = LanguageProfile(
            id: UUID(),
            name: "P",
            inputLanguageCode: "en",
            transcriptionURLOverride: "",
            transcriptionModelOverride: "",
            realtimeModelOverride: "",
            postProcessingPromptOverride: ""
        )
        let globals = LanguageProfileGlobalDefaults(
            transcriptionBaseURL: "",
            transcriptionAPIKey: "",
            transcriptionModel: "",
            realtimeModel: "",
            customSystemPrompt: ""
        )
        TestSupport.expectEqual(
            LanguageProfiles.effectiveCleanupPrompt(
                profile: profile,
                globalDefaults: globals,
                builtInDefaultPrompt: "BUILTIN"
            ),
            "BUILTIN"
        )
    }

    private static func testEffectiveTranscriptionValuesFollowOverrideRules() {
        let profile = LanguageProfile(
            id: UUID(),
            name: "P",
            inputLanguageCode: "en",
            transcriptionURLOverride: "  profile-url  ",
            transcriptionModelOverride: "   ",
            realtimeModelOverride: "profile-realtime",
            postProcessingPromptOverride: ""
        )
        let globals = LanguageProfileGlobalDefaults(
            transcriptionBaseURL: "global-url",
            transcriptionAPIKey: "global-key",
            transcriptionModel: "global-model",
            realtimeModel: "global-realtime",
            customSystemPrompt: ""
        )
        // URL: profile override wins (trimmed).
        TestSupport.expectEqual(
            LanguageProfiles.effectiveTranscriptionBaseURL(profile: profile, globalDefaults: globals),
            "profile-url"
        )
        // Model: profile override is whitespace-only, so the global
        // value is used.
        TestSupport.expectEqual(
            LanguageProfiles.effectiveTranscriptionModel(profile: profile, globalDefaults: globals),
            "global-model"
        )
        // API-key override inheritance is exercised separately by
        // `testResolutionUsesInjectedCredentialOverride` against the
        // resolver seam.
    }

    // MARK: - Live attempt orchestration

    /// Build a synthetic captured profile for the orchestration tests.
    /// Every override is set so the assertions can prove the captured
    /// values flow through unchanged rather than falling through to
    /// globals by accident.
    private static func makeOrchestrationProfile(
        url: String = "https://synthetic.example/profile-v1",
        uploadModel: String = "profile-upload-model",
        realtimeModel: String = "profile-realtime-model",
        language: String = "da",
        prompt: String = "profile-cleanup-prompt"
    ) -> ResolvedLanguageProfile {
        let globals = LanguageProfileGlobalDefaults(
            transcriptionBaseURL: "https://synthetic.example/global-v1",
            transcriptionAPIKey: "global-key",
            transcriptionModel: "global-upload-model",
            realtimeModel: "global-realtime-model",
            customSystemPrompt: "global-cleanup-prompt"
        )
        let profile = LanguageProfile(
            id: UUID(),
            name: "Profile",
            inputLanguageCode: language,
            transcriptionURLOverride: url,
            transcriptionModelOverride: uploadModel,
            realtimeModelOverride: realtimeModel,
            postProcessingPromptOverride: prompt
        )
        return LanguageProfiles.resolve(
            profile: profile,
            globalDefaults: globals,
            credentialOverride: "profile-credential"
        )
    }

    private static func testLiveAttemptConfiguresRealtimeWhenGloballyEnabled() {
        let resolved = makeOrchestrationProfile()
        let config = LiveAttemptConfigurationBuilder.configuration(
            resolvedProfile: resolved,
            realtimeStreamingEnabled: true,
            localPolicy: LocalTranscriptionPolicy(isEnabled: false)
        )
        TestSupport.expect(config.shouldStartRealtime, "Realtime should start when the global toggle is on and local policy is off")
        TestSupport.expectEqual(
            config.realtimeConfiguration?.baseURL,
            resolved.transcriptionBaseURL
        )
        TestSupport.expectEqual(
            config.realtimeConfiguration?.apiKey,
            resolved.transcriptionAPIKey
        )
        TestSupport.expectEqual(
            config.realtimeConfiguration?.model,
            resolved.realtimeModel
        )
        TestSupport.expectEqual(
            config.realtimeConfiguration?.language,
            resolved.languageHint
        )
    }

    private static func testLiveAttemptSkipsRealtimeWhenGloballyDisabled() {
        let resolved = makeOrchestrationProfile()
        let config = LiveAttemptConfigurationBuilder.configuration(
            resolvedProfile: resolved,
            realtimeStreamingEnabled: false,
            localPolicy: LocalTranscriptionPolicy(isEnabled: false)
        )
        TestSupport.expect(!config.shouldStartRealtime, "Realtime must not start when the global toggle is off")
        TestSupport.expectEqual(config.realtimeConfiguration, nil)
        // Upload transcription is unaffected by the realtime toggle —
        // the user still gets a transcript when realtime is disabled.
        // The captured upload mode sees the same endpoint, credential,
        // model, and language the realtime stream would have used.
        if case .upload(let apiKey, let baseURL, let model, let language) = config.transcriptionMode {
            TestSupport.expectEqual(baseURL, resolved.transcriptionBaseURL)
            TestSupport.expectEqual(apiKey, resolved.transcriptionAPIKey)
            TestSupport.expectEqual(model, resolved.transcriptionModel)
            TestSupport.expectEqual(language, resolved.languageHint)
        } else {
            fatalError("Expected .upload transcription mode")
        }
    }

    private static func testLiveAttemptSkipsRealtimeWhenLocalPolicyEnabled() {
        let resolved = makeOrchestrationProfile()
        let config = LiveAttemptConfigurationBuilder.configuration(
            resolvedProfile: resolved,
            realtimeStreamingEnabled: true,
            localPolicy: LocalTranscriptionPolicy(isEnabled: true)
        )
        TestSupport.expect(!config.shouldStartRealtime, "Realtime must not start when local transcription is the active policy")
        TestSupport.expectEqual(config.realtimeConfiguration, nil)
        // Local transcription is the captured mode and receives the
        // profile's language hint. Endpoint, credential, and model
        // overrides are intentionally not exposed to the local
        // recogniser — only the language code flows through.
        if case .local(let hint) = config.transcriptionMode {
            TestSupport.expectEqual(hint, resolved.languageHint)
        } else {
            fatalError("Expected .local transcription mode")
        }
    }

    private static func testLiveAttemptSkipsRealtimeWhenCapturedEndpointEmpty() {
        // Profile override is whitespace-only; resolver inherits the
        // global base URL. To exercise the "captured endpoint empty"
        // path we need a profile whose *resolved* base URL is empty,
        // so build a profile with an empty override AND globals with
        // an empty base URL.
        let globals = LanguageProfileGlobalDefaults(
            transcriptionBaseURL: "",
            transcriptionAPIKey: "global-key",
            transcriptionModel: "global-upload-model",
            realtimeModel: "global-realtime-model",
            customSystemPrompt: ""
        )
        let profile = LanguageProfile(
            id: UUID(),
            name: "Empty",
            inputLanguageCode: "en",
            transcriptionURLOverride: "",
            transcriptionModelOverride: "",
            realtimeModelOverride: "",
            postProcessingPromptOverride: ""
        )
        let resolved = LanguageProfiles.resolve(
            profile: profile,
            globalDefaults: globals,
            credentialOverride: ""
        )
        TestSupport.expectEqual(resolved.transcriptionBaseURL, "")
        let config = LiveAttemptConfigurationBuilder.configuration(
            resolvedProfile: resolved,
            realtimeStreamingEnabled: true,
            localPolicy: LocalTranscriptionPolicy(isEnabled: false)
        )
        TestSupport.expect(!config.shouldStartRealtime, "Realtime must not start when the resolved endpoint is empty")
        TestSupport.expectEqual(config.realtimeConfiguration, nil)
    }

    private static func testLiveAttemptUsesCapturedProfileEndpointCredentialModelAndLanguage() {
        // Profile with non-empty overrides wins over the globals for
        // endpoint, credential, model, and language hint.
        let resolved = makeOrchestrationProfile(
            url: "https://synthetic.example/profile-only",
            uploadModel: "profile-only-upload",
            realtimeModel: "profile-only-realtime",
            language: "ja",
            prompt: "profile-only-prompt"
        )
        let config = LiveAttemptConfigurationBuilder.configuration(
            resolvedProfile: resolved,
            realtimeStreamingEnabled: true,
            localPolicy: LocalTranscriptionPolicy(isEnabled: false)
        )
        // Realtime receives the captured values verbatim.
        TestSupport.expectEqual(
            config.realtimeConfiguration?.baseURL,
            "https://synthetic.example/profile-only"
        )
        TestSupport.expectEqual(
            config.realtimeConfiguration?.model,
            "profile-only-realtime"
        )
        TestSupport.expectEqual(
            config.realtimeConfiguration?.language,
            "ja"
        )
        TestSupport.expectEqual(
            config.realtimeConfiguration?.apiKey,
            resolved.transcriptionAPIKey
        )
        // The captured upload mode also sees the captured profile
        // values verbatim.
        if case .upload(let apiKey, let baseURL, let model, let language) = config.transcriptionMode {
            TestSupport.expectEqual(baseURL, "https://synthetic.example/profile-only")
            TestSupport.expectEqual(model, "profile-only-upload")
            TestSupport.expectEqual(language, "ja")
            TestSupport.expectEqual(apiKey, resolved.transcriptionAPIKey)
        } else {
            fatalError("Expected .upload transcription mode")
        }
        // Cleanup prompt reflects the profile's override.
        TestSupport.expectEqual(
            config.ordinaryCleanupSystemPrompt,
            "profile-only-prompt"
        )
        // Profile identity preserved for history / debug surfaces.
        TestSupport.expectEqual(config.profileID, resolved.profileID)
        TestSupport.expectEqual(config.profileName, resolved.profileName)
    }

    private static func testLiveAttemptUploadFallbackMatchesRealtimeConfiguration() {
        // Shared fallback contract: the upload transcription mode must
        // always receive the same endpoint, credential, model, and
        // language the realtime stream was started with, so a realtime
        // failure transparently falls back without reconfiguration.
        // Verify both code paths (realtime enabled vs disabled) yield
        // the same captured upload values.
        let resolved = makeOrchestrationProfile()
        let withRealtime = LiveAttemptConfigurationBuilder.configuration(
            resolvedProfile: resolved,
            realtimeStreamingEnabled: true,
            localPolicy: LocalTranscriptionPolicy(isEnabled: false)
        )
        let withoutRealtime = LiveAttemptConfigurationBuilder.configuration(
            resolvedProfile: resolved,
            realtimeStreamingEnabled: false,
            localPolicy: LocalTranscriptionPolicy(isEnabled: false)
        )
        TestSupport.expectEqual(withRealtime.transcriptionMode, withoutRealtime.transcriptionMode)
        if case .upload(let apiKey, let baseURL, let model, let language) = withRealtime.transcriptionMode {
            TestSupport.expectEqual(baseURL, resolved.transcriptionBaseURL)
            TestSupport.expectEqual(apiKey, resolved.transcriptionAPIKey)
            TestSupport.expectEqual(model, resolved.transcriptionModel)
            TestSupport.expectEqual(language, resolved.languageHint)
        } else {
            fatalError("Expected .upload transcription mode")
        }
        // Cleanup prompt also stays the same regardless of realtime
        // gating.
        TestSupport.expectEqual(
            withRealtime.ordinaryCleanupSystemPrompt,
            withoutRealtime.ordinaryCleanupSystemPrompt
        )
    }

    private static func testLiveAttemptIsImmutableAcrossSettingsEdits() {
        // Simulate the recording-start → settings-edit-during-recording
        // scenario: capture a profile once, build the configuration
        // immediately, then "edit" the inputs that settings UI might
        // touch (catalog, globals, credential store) and rebuild from
        // the original captured profile. The configuration must be
        // identical field-for-field, proving the pipeline consumes
        // only the snapshot, never live settings.
        let resolved = makeOrchestrationProfile()
        let snapshot = LiveAttemptConfigurationBuilder.configuration(
            resolvedProfile: resolved,
            realtimeStreamingEnabled: true,
            localPolicy: LocalTranscriptionPolicy(isEnabled: false)
        )
        let frozenSnapshot = snapshot

        // Edit the catalog to a fully-different profile — a would-be
        // live resolution would now return this profile's values, so
        // any reliance on the catalog (rather than the captured
        // snapshot) would surface here.
        let replacementID = UUID()
        let replacementProfile = LanguageProfile(
            id: replacementID,
            name: "Replacement",
            inputLanguageCode: "fr",
            transcriptionURLOverride: "https://synthetic.example/replacement",
            transcriptionModelOverride: "replacement-upload",
            realtimeModelOverride: "replacement-realtime",
            postProcessingPromptOverride: "replacement-prompt"
        )
        let replacementCatalog = LanguageProfileCatalog(
            profiles: [replacementProfile],
            activeProfileID: replacementID
        )
        TestSupport.expectEqual(
            replacementCatalog.resolvedActiveProfile(
                globalDefaults: LanguageProfileGlobalDefaults(
                    transcriptionBaseURL: "https://synthetic.example/global-v2",
                    transcriptionAPIKey: "global-key-2",
                    transcriptionModel: "global-upload-model-2",
                    realtimeModel: "global-realtime-model-2",
                    customSystemPrompt: ""
                ),
                credentials: InMemoryCredentialStore(values: [replacementID: "replacement-credential"])
            ).transcriptionBaseURL,
            "https://synthetic.example/replacement"
        )
        TestSupport.expect(
            replacementCatalog.profiles[0].id != resolved.profileID,
            "Replacement catalog must not contain the originally captured profile"
        )

        // Rebuild from the originally captured profile only.
        let replay = LiveAttemptConfigurationBuilder.configuration(
            resolvedProfile: resolved,
            realtimeStreamingEnabled: true,
            localPolicy: LocalTranscriptionPolicy(isEnabled: false)
        )

        TestSupport.expectEqual(replay, frozenSnapshot)
        if case .upload(let apiKey, let baseURL, let model, let language) = replay.transcriptionMode {
            TestSupport.expectEqual(baseURL, resolved.transcriptionBaseURL)
            TestSupport.expectEqual(apiKey, resolved.transcriptionAPIKey)
            TestSupport.expectEqual(model, resolved.transcriptionModel)
            TestSupport.expectEqual(language, resolved.languageHint)
        } else {
            fatalError("Expected .upload transcription mode")
        }
        TestSupport.expectEqual(
            replay.ordinaryCleanupSystemPrompt,
            resolved.ordinaryCleanupSystemPrompt
        )
        TestSupport.expectEqual(
            replay.realtimeConfiguration?.baseURL,
            resolved.transcriptionBaseURL
        )
        TestSupport.expectEqual(
            replay.realtimeConfiguration?.apiKey,
            resolved.transcriptionAPIKey
        )
        TestSupport.expectEqual(
            replay.realtimeConfiguration?.model,
            resolved.realtimeModel
        )
        TestSupport.expectEqual(
            replay.realtimeConfiguration?.language,
            resolved.languageHint
        )
    }

    private static func testLiveAttemptLocalTranscriptionUsesLanguageHintOnly() {
        // When local transcription is the active policy, realtime is
        // never configured but local mode still consumes the profile's
        // language hint. Endpoint, credential, and model overrides
        // must not flow into the local transcription mode; only the
        // language code does.
        let resolved = makeOrchestrationProfile(
            url: "https://synthetic.example/profile-v1",
            uploadModel: "profile-upload-model",
            realtimeModel: "profile-realtime-model",
            language: "de",
            prompt: "profile-cleanup-prompt"
        )
        let config = LiveAttemptConfigurationBuilder.configuration(
            resolvedProfile: resolved,
            realtimeStreamingEnabled: true,
            localPolicy: LocalTranscriptionPolicy(isEnabled: true)
        )
        TestSupport.expect(!config.shouldStartRealtime, "Local policy must not start realtime")
        TestSupport.expectEqual(config.realtimeConfiguration, nil)
        // Only the language hint flows through to local transcription;
        // the endpoint, credential, and model overrides never reach
        // the local recogniser.
        if case .local(let hint) = config.transcriptionMode {
            TestSupport.expectEqual(hint, "de")
        } else {
            fatalError("Expected .local transcription mode")
        }
        // Cleanup prompt still reflects the profile's override so
        // the post-processing pipeline sees the profile's voice.
        TestSupport.expectEqual(
            config.ordinaryCleanupSystemPrompt,
            "profile-cleanup-prompt"
        )

        // Auto-detect profile (empty input language) → nil language
        // hint for the local recogniser, never a synthetic default.
        let autoProfile = makeOrchestrationProfile(language: "")
        let autoConfig = LiveAttemptConfigurationBuilder.configuration(
            resolvedProfile: autoProfile,
            realtimeStreamingEnabled: false,
            localPolicy: LocalTranscriptionPolicy(isEnabled: true)
        )
        if case .local(let hint) = autoConfig.transcriptionMode {
            TestSupport.expectEqual(hint, nil)
        } else {
            fatalError("Expected .local transcription mode for auto-detect profile")
        }
    }

    private static func testLiveAttemptCapturesTranscriptionMode() {
        // The transcription mode is decided at recording start from the
        // captured profile plus the `localPolicy` snapshot. A settings
        // toggle that flips `localTranscriptionEnabled` while the
        // attempt is in flight must not be able to swap a locally-
        // started attempt to an upload one (or vice versa). Verify
        // both branches and that the captured values flow through
        // unchanged.
        let resolved = makeOrchestrationProfile()

        // Local transcription enabled → mode should be .local with the
        // profile's captured language hint.
        let localConfig = LiveAttemptConfigurationBuilder.configuration(
            resolvedProfile: resolved,
            realtimeStreamingEnabled: false,
            localPolicy: LocalTranscriptionPolicy(isEnabled: true)
        )
        if case .local(let hint) = localConfig.transcriptionMode {
            TestSupport.expectEqual(hint, resolved.languageHint)
        } else {
            fatalError("Expected .local transcription mode")
        }

        // Local transcription disabled → mode should be .upload with
        // the captured profile's endpoint, credential, model, and
        // language — nothing falls back to globals.
        let uploadConfig = LiveAttemptConfigurationBuilder.configuration(
            resolvedProfile: resolved,
            realtimeStreamingEnabled: false,
            localPolicy: LocalTranscriptionPolicy(isEnabled: false)
        )
        if case .upload(let apiKey, let baseURL, let model, let language) = uploadConfig.transcriptionMode {
            TestSupport.expectEqual(apiKey, resolved.transcriptionAPIKey)
            TestSupport.expectEqual(baseURL, resolved.transcriptionBaseURL)
            TestSupport.expectEqual(model, resolved.transcriptionModel)
            TestSupport.expectEqual(language, resolved.languageHint)
        } else {
            fatalError("Expected .upload transcription mode")
        }
    }

    private static func testLiveAttemptTranslationIndependence() {
        // Output Language (translation) is a separate global input to
        // post-processing. It must not be selected, stored, or
        // influenced by the active profile. The pure helper exposes
        // no Output Language field — only profile identity, the
        // captured transcription mode (local or upload), the cleanup
        // prompt, and the realtime decision. Translation flows from
        // `AppState.outputLanguage` directly into `processTranscript`
        // and is never read from the captured profile.
        //
        // `LanguageProfile` and `ResolvedLanguageProfile` carry no
        // output-language field at all (the struct does not declare
        // one). Build configurations from two profiles that differ
        // only in their input language code and confirm the only
        // difference is the input-language-derived fields — no other
        // field changes, proving translation is independent.
        let globals = LanguageProfileGlobalDefaults(
            transcriptionBaseURL: "https://synthetic.example/v1",
            transcriptionAPIKey: "synthetic-key",
            transcriptionModel: "whisper-large-v3",
            realtimeModel: "whisper-large-v3",
            customSystemPrompt: "global prompt"
        )
        let englishProfile = LanguageProfile(
            id: UUID(),
            name: "English",
            inputLanguageCode: "en",
            transcriptionURLOverride: "",
            transcriptionModelOverride: "",
            realtimeModelOverride: "",
            postProcessingPromptOverride: ""
        )
        let japaneseProfile = LanguageProfile(
            id: UUID(),
            name: "Japanese",
            inputLanguageCode: "ja",
            transcriptionURLOverride: "",
            transcriptionModelOverride: "",
            realtimeModelOverride: "",
            postProcessingPromptOverride: ""
        )
        let englishResolved = LanguageProfiles.resolve(
            profile: englishProfile,
            globalDefaults: globals,
            credentialOverride: ""
        )
        let japaneseResolved = LanguageProfiles.resolve(
            profile: japaneseProfile,
            globalDefaults: globals,
            credentialOverride: ""
        )
        let englishConfig = LiveAttemptConfigurationBuilder.configuration(
            resolvedProfile: englishResolved,
            realtimeStreamingEnabled: false,
            localPolicy: LocalTranscriptionPolicy(isEnabled: false)
        )
        let japaneseConfig = LiveAttemptConfigurationBuilder.configuration(
            resolvedProfile: japaneseResolved,
            realtimeStreamingEnabled: false,
            localPolicy: LocalTranscriptionPolicy(isEnabled: false)
        )
        // Upload transcription values are identical except for the language
        // derived from the profile.
        if case .upload(let englishAPIKey, let englishBaseURL, let englishModel, let englishLanguage) = englishConfig.transcriptionMode,
           case .upload(let japaneseAPIKey, let japaneseBaseURL, let japaneseModel, let japaneseLanguage) = japaneseConfig.transcriptionMode {
            TestSupport.expectEqual(englishBaseURL, japaneseBaseURL)
            TestSupport.expectEqual(englishAPIKey, japaneseAPIKey)
            TestSupport.expectEqual(englishModel, japaneseModel)
            TestSupport.expectEqual(englishLanguage, "en")
            TestSupport.expectEqual(japaneseLanguage, "ja")
        } else {
            fatalError("Expected .upload transcription mode for both language profiles")
        }
        // Cleanup prompt is the same regardless of input language.
        TestSupport.expectEqual(
            englishConfig.ordinaryCleanupSystemPrompt,
            japaneseConfig.ordinaryCleanupSystemPrompt
        )
        // Local transcription mode would carry the input language hint
        // but is not the captured mode here; rebuild each config with
        // local policy on to confirm the hint flows through and is
        // *not* a translation target.
        let englishLocalConfig = LiveAttemptConfigurationBuilder.configuration(
            resolvedProfile: englishResolved,
            realtimeStreamingEnabled: false,
            localPolicy: LocalTranscriptionPolicy(isEnabled: true)
        )
        let japaneseLocalConfig = LiveAttemptConfigurationBuilder.configuration(
            resolvedProfile: japaneseResolved,
            realtimeStreamingEnabled: false,
            localPolicy: LocalTranscriptionPolicy(isEnabled: true)
        )
        if case .local(let englishHint) = englishLocalConfig.transcriptionMode {
            TestSupport.expectEqual(englishHint, "en")
        } else {
            fatalError("Expected .local transcription mode for English profile")
        }
        if case .local(let japaneseHint) = japaneseLocalConfig.transcriptionMode {
            TestSupport.expectEqual(japaneseHint, "ja")
        } else {
            fatalError("Expected .local transcription mode for Japanese profile")
        }
    }
}