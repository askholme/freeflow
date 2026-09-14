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

        func setOverride(_ value: String?, for profileID: UUID) {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if trimmed.isEmpty {
                values.removeValue(forKey: profileID)
            } else {
                values[profileID] = trimmed
            }
        }

        func loadAPIKeyOverride(profileID: UUID) -> String? {
            values[profileID]
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

        store.setOverride("  profile-key  ", for: profileID)
        let overridden = LanguageProfiles.resolve(
            profile: profile,
            globalDefaults: globals,
            credentialOverride: store.loadAPIKeyOverride(profileID: profileID) ?? ""
        )
        TestSupport.expectEqual(overridden.transcriptionAPIKey, "profile-key")

        store.setOverride("   ", for: profileID)
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
        store.setOverride("profile-key-2", for: profileID)

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
}