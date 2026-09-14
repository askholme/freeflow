import Foundation

/// One persisted, user-named configuration for a single input language.
///
/// A `LanguageProfile` carries optional, non-secret overrides for the
/// transcription endpoint, upload model, realtime model, and ordinary
/// dictation-cleanup prompt. Empty or whitespace-only overrides inherit the
/// corresponding global setting. The API-key override is intentionally
/// **not** stored on the profile: credentials are resolved through an
/// injected `LanguageProfileCredentialStore` so they never travel through
/// profile JSON, history, exports, or logs.
///
/// The empty `inputLanguageCode` represents Auto-detect; at most one
/// Auto-detect profile may exist at a time.
struct LanguageProfile: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    /// Empty string means Auto-detect; non-empty values must be one of
    /// `LanguageProfiles.supportedInputLanguages`.
    var inputLanguageCode: String
    /// Empty means inherit the global transcription base URL.
    var transcriptionURLOverride: String
    /// Upload-model override. Empty means inherit the global transcription model.
    var transcriptionModelOverride: String
    /// Realtime-model override. Empty means inherit the global realtime model.
    var realtimeModelOverride: String
    /// Ordinary dictation-cleanup prompt override. Empty means inherit the
    /// global custom system prompt; if that is also empty the post-processing
    /// service uses its built-in default prompt. This override does not apply
    /// to Edit Mode's command-transform prompt.
    var postProcessingPromptOverride: String
}

/// Ordered catalog of `LanguageProfile`s plus the identity of the
/// currently `Active Profile`.
///
/// Invariants enforced by `LanguageProfiles.loadCatalog(from:)`:
/// - `profiles` is non-empty (at least one profile always remains);
/// - profile names are trimmed and unique using case-insensitive comparison;
/// - `inputLanguageCode` values are unique across profiles, so at most one
///   Auto-detect profile can exist;
/// - `activeProfileID` always identifies a member of `profiles`.
struct LanguageProfileCatalog: Equatable {
    var profiles: [LanguageProfile]
    var activeProfileID: UUID

    /// The currently `Active Profile`. `first(where:)` is the canonical
    /// lookup; the `?? profiles[0]` fallback makes this a total accessor
    /// even when an upstream invariant is broken, so callers can rely on
    /// a defined value while the catalog is in flight.
    var activeProfile: LanguageProfile {
        profiles.first(where: { $0.id == activeProfileID }) ?? profiles[0]
    }
}

/// Global defaults fed into the resolver alongside one `LanguageProfile`.
///
/// These are the same values `AppState` already exposes as its resolved
/// transcription endpoint, API key, upload model, realtime model, and
/// global custom system prompt. The resolver combines them with the
/// profile's per-field overrides to produce an immutable
/// `ResolvedLanguageProfile` for a Processing Attempt.
///
/// Output Language is deliberately NOT part of these defaults: it is a
/// separate global input to post-processing and is never changed by a
/// profile.
struct LanguageProfileGlobalDefaults {
    var transcriptionBaseURL: String
    var transcriptionAPIKey: String
    var transcriptionModel: String
    var realtimeModel: String
    var customSystemPrompt: String
}

/// Immutable snapshot of one resolved Language Profile for a single
/// Processing Attempt. All properties are `let` so a captured snapshot
/// cannot be mutated after a Processing Attempt begins — settings edits
/// during the attempt therefore cannot mix old and new configurations.
///
/// The resolved API key is intentionally a `let` here only because the
/// snapshot is captured once; callers must never persist, log, or export
/// `transcriptionAPIKey`.
struct ResolvedLanguageProfile: Equatable {
    let profileID: UUID
    let profileName: String
    let inputLanguageCode: String
    /// `nil` when the profile selects Auto-detect; otherwise the
    /// normalized `inputLanguageCode` (trimmed, lowercased, and
    /// validated against `LanguageProfiles.supportedInputLanguages`) ready
    /// to hand to the transcription backend.
    let languageHint: String?
    let transcriptionBaseURL: String
    let transcriptionAPIKey: String
    let transcriptionModel: String
    let realtimeModel: String
    /// The ordinary dictation-cleanup prompt to pass to
    /// `PostProcessingService.postProcess`: the profile override when
    /// non-empty, otherwise the inherited global custom prompt. An empty
    /// value here means the post-processing service uses its built-in
    /// default prompt. Never used for Edit Mode's command-transform
    /// prompt, which has its own dedicated contract.
    let ordinaryCleanupSystemPrompt: String
}

/// Identifies which post-processing prompt path the caller is on.
/// Profile prompt overrides apply only to ordinary dictation cleanup;
/// Edit Mode's command-transform prompt is always its dedicated,
/// profile-independent prompt.
enum LanguageProfileCleanupScope {
    case ordinaryDictation
    case editModeCommandTransform
}

/// Injected boundary through which Language Profile API-key overrides are
/// resolved at snapshot time. Credentials never travel through profile
/// JSON, history, exports, or logs.
///
/// In production this is bridged to the existing `AppSettingsStorage`
/// (owner-only application-support `.settings` file). Profile management
/// UI will extend this protocol with mutation later.
protocol LanguageProfileCredentialStore {
    func loadAPIKeyOverride(profileID: UUID) -> String?
}

extension LanguageProfileCatalog {
    /// Resolve the active profile using the supplied global defaults and
    /// the injected credential store. The credential override is loaded
    /// once at snapshot time and becomes part of the immutable snapshot.
    func resolvedActiveProfile(
        globalDefaults: LanguageProfileGlobalDefaults,
        credentials: LanguageProfileCredentialStore
    ) -> ResolvedLanguageProfile {
        let active = activeProfile
        let credentialOverride = credentials.loadAPIKeyOverride(profileID: active.id) ?? ""
        return LanguageProfiles.resolve(
            profile: active,
            globalDefaults: globalDefaults,
            credentialOverride: credentialOverride
        )
    }
}

/// Namespace housing the language-profile domain logic. Modeled as a
/// caseless enum (like `ModelConfiguration`) so all members are namespaced
/// without exposing an instance type.
enum LanguageProfiles {

    // MARK: Supported languages

    /// Single source of truth for the supported input languages. Order
    /// matters for the Settings UI picker and for Auto-detect being the
    /// first (empty-code) entry.
    static let supportedInputLanguages: [(code: String, name: String)] = [
        ("", "Auto-detect"),
        ("en", "English"),
        ("es", "Spanish"),
        ("fr", "French"),
        ("de", "German"),
        ("it", "Italian"),
        ("pt", "Portuguese"),
        ("nl", "Dutch"),
        ("ru", "Russian"),
        ("ja", "Japanese"),
        ("ko", "Korean"),
        ("zh", "Chinese"),
        ("ar", "Arabic"),
        ("hi", "Hindi"),
        ("tr", "Turkish"),
        ("pl", "Polish"),
        ("uk", "Ukrainian"),
        ("sv", "Swedish"),
        ("no", "Norwegian"),
        ("da", "Danish"),
        ("fi", "Finnish"),
        ("cs", "Czech"),
        ("el", "Greek"),
        ("he", "Hebrew"),
        ("vi", "Vietnamese"),
        ("th", "Thai"),
        ("id", "Indonesian"),
        ("ro", "Romanian"),
        ("hu", "Hungarian"),
        ("ca", "Catalan")
    ]

    /// Trim, lowercase, and validate against `supportedInputLanguages`.
    /// Returns the normalized code when supported, otherwise `""`
    /// (Auto-detect).
    static func normalizeInputLanguageCode(_ code: String) -> String {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard supportedInputLanguages.contains(where: { $0.code == normalized }) else {
            return ""
        }
        return normalized
    }

    // MARK: Stored-state inputs

    /// Raw values pulled from the host's persistence layer and injected
    /// into `loadCatalog(from:)`. Tests pass synthetic values instead of
    /// touching `UserDefaults` or `AppSettingsStorage`.
    struct StoredLanguageProfileState {
        let profilesData: Data?
        let activeProfileID: String?
        let legacyTranscriptionLanguage: String
    }

    /// Result of loading and repairing the stored catalog. Callers
    /// persist when `didRepairStoredValue` is true so the next launch
    /// sees the corrected values without re-running repair.
    struct LoadedLanguageProfileCatalog {
        let catalog: LanguageProfileCatalog
        let didRepairStoredValue: Bool
    }

    // MARK: Loading / repair

    /// Deterministically load the persisted profile catalog from raw
    /// stored inputs, normalizing fields and repairing any invariant
    /// violation so the result always satisfies the catalog invariants.
    ///
    /// Repair steps:
    /// 1. Decode `[LanguageProfile]` from `profilesData`. Nil or decode
    ///    failure yields an empty candidate list.
    /// 2. Normalize each candidate: trim name and override strings,
    ///    normalize `inputLanguageCode` via `normalizeInputLanguageCode`.
    /// 3. Keep candidates in order, skipping ones that violate
    ///    uniqueness / non-empty-name rules.
    /// 4. If nothing remains, seed exactly one Default profile from the
    ///    legacy input language so the catalog is never empty.
    /// 5. Repair the active ID to the first kept profile when missing,
    ///    malformed, or unknown.
    static func loadCatalog(from state: StoredLanguageProfileState) -> LoadedLanguageProfileCatalog {
        let decoded: [LanguageProfile]
        var decodedCount = 0
        if let profilesData = state.profilesData {
            if let array = try? JSONDecoder().decode([LanguageProfile].self, from: profilesData) {
                decoded = array
                decodedCount = array.count
            } else {
                decoded = []
            }
        } else {
            decoded = []
        }

        var keptProfiles: [LanguageProfile] = []
        var seenIDs: Set<UUID> = []
        var seenNamesLowercase: Set<String> = []
        var seenCodes: Set<String> = []
        var didAnyNormalizationChange = false

        for candidate in decoded {
            let normalizedName = candidate.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedCode = normalizeInputLanguageCode(candidate.inputLanguageCode)
            let normalizedURL = candidate.transcriptionURLOverride.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedUploadModel = candidate.transcriptionModelOverride.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedRealtimeModel = candidate.realtimeModelOverride.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedPrompt = candidate.postProcessingPromptOverride.trimmingCharacters(in: .whitespacesAndNewlines)

            if normalizedName.isEmpty
                || seenIDs.contains(candidate.id)
                || seenNamesLowercase.contains(normalizedName.lowercased())
                || seenCodes.contains(normalizedCode) {
                continue
            }

            let normalizationChanged =
                normalizedName != candidate.name
                || normalizedCode != candidate.inputLanguageCode
                || normalizedURL != candidate.transcriptionURLOverride
                || normalizedUploadModel != candidate.transcriptionModelOverride
                || normalizedRealtimeModel != candidate.realtimeModelOverride
                || normalizedPrompt != candidate.postProcessingPromptOverride
            if normalizationChanged {
                didAnyNormalizationChange = true
            }

            seenIDs.insert(candidate.id)
            seenNamesLowercase.insert(normalizedName.lowercased())
            seenCodes.insert(normalizedCode)

            keptProfiles.append(
                LanguageProfile(
                    id: candidate.id,
                    name: normalizedName,
                    inputLanguageCode: normalizedCode,
                    transcriptionURLOverride: normalizedURL,
                    transcriptionModelOverride: normalizedUploadModel,
                    realtimeModelOverride: normalizedRealtimeModel,
                    postProcessingPromptOverride: normalizedPrompt
                )
            )
        }

        let seeded: Bool
        if keptProfiles.isEmpty {
            seeded = true
            let legacyCode = normalizeInputLanguageCode(state.legacyTranscriptionLanguage)
            keptProfiles = [
                LanguageProfile(
                    id: UUID(),
                    name: "Default",
                    inputLanguageCode: legacyCode,
                    transcriptionURLOverride: "",
                    transcriptionModelOverride: "",
                    realtimeModelOverride: "",
                    postProcessingPromptOverride: ""
                )
            ]
        } else {
            seeded = false
        }

        let keptIDs = Set(keptProfiles.map(\.id))
        let parsedActive = state.activeProfileID.flatMap(UUID.init(uuidString:))
        let activeID: UUID
        let didRepairActive: Bool
        if let parsedActive, keptIDs.contains(parsedActive) {
            activeID = parsedActive
            didRepairActive = false
        } else {
            // Active ID had to be repaired because the stored value was
            // missing, malformed, or no longer identifies a kept profile.
            activeID = keptProfiles[0].id
            didRepairActive = true
        }

        let catalog = LanguageProfileCatalog(
            profiles: keptProfiles,
            activeProfileID: activeID
        )

        let didRepairStoredValue =
            seeded
            || keptProfiles.count != decodedCount
            || didAnyNormalizationChange
            || didRepairActive

        return LoadedLanguageProfileCatalog(
            catalog: catalog,
            didRepairStoredValue: didRepairStoredValue
        )
    }

    // MARK: Resolution

    /// Pure resolver: combine one profile with the supplied global
    /// defaults and the per-profile API-key override into an immutable
    /// `ResolvedLanguageProfile`. Trimming keeps overrides and globals
    /// comparable on whitespace, and the input language code is run
    /// through `normalizeInputLanguageCode` so direct callers of the
    /// resolver always observe a supported lowercase code (or `""` for
    /// Auto-detect) — matching the catalog-load repair path and the
    /// ticket's "supported input-language codes are normalized" rule.
    static func resolve(
        profile: LanguageProfile,
        globalDefaults: LanguageProfileGlobalDefaults,
        credentialOverride: String
    ) -> ResolvedLanguageProfile {
        let url = inherit(profile.transcriptionURLOverride, globalDefaults.transcriptionBaseURL)
        let apiKey = inherit(credentialOverride, globalDefaults.transcriptionAPIKey)
        let uploadModel = inherit(profile.transcriptionModelOverride, globalDefaults.transcriptionModel)
        let realtimeModel = inherit(profile.realtimeModelOverride, globalDefaults.realtimeModel)
        let prompt = inherit(profile.postProcessingPromptOverride, globalDefaults.customSystemPrompt)
        let normalizedCode = normalizeInputLanguageCode(profile.inputLanguageCode)
        let languageHint: String? = normalizedCode.isEmpty ? nil : normalizedCode

        return ResolvedLanguageProfile(
            profileID: profile.id,
            profileName: profile.name,
            inputLanguageCode: normalizedCode,
            languageHint: languageHint,
            transcriptionBaseURL: url,
            transcriptionAPIKey: apiKey,
            transcriptionModel: uploadModel,
            realtimeModel: realtimeModel,
            ordinaryCleanupSystemPrompt: prompt
        )
    }

    /// Pick the profile override when non-empty, otherwise inherit the
    /// global value. Both inputs are trimmed for safe comparison and to
    /// keep whitespace-only overrides from masquerading as a real value.
    private static func inherit(_ override: String, _ global: String) -> String {
        let trimmedOverride = override.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedOverride.isEmpty {
            return trimmedOverride
        }
        return global.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Prompt scope

    /// Resolve the system prompt to pass to the post-processing service
    /// for the given cleanup scope. Profile prompt overrides apply only
    /// to ordinary dictation cleanup; Edit Mode always uses its dedicated
    /// command-transform prompt and never sees a profile or global custom
    /// prompt here.
    static func customSystemPrompt(
        for scope: LanguageProfileCleanupScope,
        resolvedProfile: ResolvedLanguageProfile
    ) -> String {
        switch scope {
        case .ordinaryDictation:
            return resolvedProfile.ordinaryCleanupSystemPrompt
        case .editModeCommandTransform:
            return ""
        }
    }
}