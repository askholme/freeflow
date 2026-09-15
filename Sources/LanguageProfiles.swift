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

/// User-presentable validation error returned by `LanguageProfiles`
/// management operations. The `message` value is suitable for inline
/// Settings UI feedback. Callers should not construct these directly;
/// they are produced by the domain operations on invalid input.
enum LanguageProfileValidationError: Error, Equatable {
    case emptyName
    case duplicateName(existingProfileID: UUID, existingProfileName: String)
    case unsupportedLanguageCode(code: String)
    case duplicateLanguageCode(existingProfileID: UUID, existingProfileName: String)
    case unknownProfileID(UUID)
    case cannotDeleteFinalProfile
    case invalidReorderIndex

    var message: String {
        switch self {
        case .emptyName:
            return "Profile name cannot be empty."
        case .duplicateName(_, let existingProfileName):
            return "Another profile is already named \"\(existingProfileName)\"."
        case .unsupportedLanguageCode(let code):
            return "Unsupported input language code: \(code.isEmpty ? "(blank)" : code)."
        case .duplicateLanguageCode(_, let existingProfileName):
            return "Another profile already uses this language (\(existingProfileName))."
        case .unknownProfileID(let id):
            return "Unknown profile ID: \(id.uuidString)."
        case .cannotDeleteFinalProfile:
            return "You must keep at least one profile."
        case .invalidReorderIndex:
            return "Cannot move the profile beyond the ordered list."
        }
    }
}

/// Direction for `LanguageProfiles.reorderProfile`. `up` moves the
/// profile toward the start of the ordered list; `down` moves it
/// toward the end.
enum LanguageProfileReorderDirection {
    case up
    case down
}

/// Injected boundary through which Language Profile API-key overrides
/// are resolved at snapshot time and persisted through profile
/// management UI. Credentials never travel through profile JSON,
/// history, exports, or logs.
///
/// In production this is bridged to the existing `AppSettingsStorage`
/// (owner-only application-support `.settings` file). Profile management
/// UI uses `setAPIKeyOverride(_:profileID:)` and
/// `clearAPIKeyOverride(profileID:)` to persist per-profile credential
/// overrides without leaking them through other storage paths.
protocol LanguageProfileCredentialStore {
    func loadAPIKeyOverride(profileID: UUID) -> String?
    func setAPIKeyOverride(_ value: String, profileID: UUID)
    func clearAPIKeyOverride(profileID: UUID)
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

    // MARK: Management operations

    /// Add a new profile with the given name and input-language code to
    /// the catalog. The new profile becomes the Active Profile so the
    /// user can immediately test it. Each rejection produces a typed
    /// `LanguageProfileValidationError` whose `message` is suitable for
    /// inline UI feedback.
    ///
    /// - The name is trimmed; an empty trimmed name is rejected.
    /// - The code must be one of `supportedInputLanguages` (Auto-detect
    ///   is `""` and is supported). Anything else is rejected so callers
    ///   cannot silently fall back to Auto-detect by passing an
    ///   unsupported code.
    /// - The code must not already be used by another profile in the
    ///   catalog (this also rejects a second Auto-detect profile since
    ///   the empty code is shared).
    static func addProfile(
        name: String,
        inputLanguageCode: String,
        to catalog: LanguageProfileCatalog
    ) -> Result<(catalog: LanguageProfileCatalog, profile: LanguageProfile), LanguageProfileValidationError> {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            return .failure(.emptyName)
        }
        let trimmedCode = inputLanguageCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard supportedInputLanguages.contains(where: { $0.code == trimmedCode }) else {
            return .failure(.unsupportedLanguageCode(code: trimmedCode))
        }
        if let existing = catalog.profiles.first(where: { $0.inputLanguageCode == trimmedCode }) {
            return .failure(.duplicateLanguageCode(
                existingProfileID: existing.id,
                existingProfileName: existing.name
            ))
        }
        let nameKey = trimmedName.lowercased()
        if let existing = catalog.profiles.first(where: { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == nameKey }) {
            return .failure(.duplicateName(
                existingProfileID: existing.id,
                existingProfileName: existing.name
            ))
        }
        let profile = LanguageProfile(
            id: UUID(),
            name: trimmedName,
            inputLanguageCode: trimmedCode,
            transcriptionURLOverride: "",
            transcriptionModelOverride: "",
            realtimeModelOverride: "",
            postProcessingPromptOverride: ""
        )
        var newProfiles = catalog.profiles
        newProfiles.append(profile)
        let newCatalog = LanguageProfileCatalog(
            profiles: newProfiles,
            activeProfileID: profile.id
        )
        return .success((catalog: newCatalog, profile: profile))
    }

    /// Rename an existing profile. The new name is trimmed; an empty
    /// trimmed name or a duplicate (case-insensitive against any other
    /// profile's trimmed name) is rejected. Renaming a profile to its
    /// own current name is a no-op success.
    static func renameProfile(
        in catalog: LanguageProfileCatalog,
        id: UUID,
        newName: String
    ) -> Result<LanguageProfileCatalog, LanguageProfileValidationError> {
        guard let index = catalog.profiles.firstIndex(where: { $0.id == id }) else {
            return .failure(.unknownProfileID(id))
        }
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            return .failure(.emptyName)
        }
        let nameKey = trimmedName.lowercased()
        for (otherIndex, other) in catalog.profiles.enumerated() where otherIndex != index {
            if other.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == nameKey {
                return .failure(.duplicateName(
                    existingProfileID: other.id,
                    existingProfileName: other.name
                ))
            }
        }
        if catalog.profiles[index].name == trimmedName {
            return .success(catalog)
        }
        var newProfiles = catalog.profiles
        var updated = newProfiles[index]
        updated.name = trimmedName
        newProfiles[index] = updated
        return .success(LanguageProfileCatalog(
            profiles: newProfiles,
            activeProfileID: catalog.activeProfileID
        ))
    }

    /// Move a profile one step in the requested direction within the
    /// ordered list. Rejects the move at the bounds (top cannot move up,
    /// bottom cannot move down) so callers can show inline feedback
    /// instead of silently clamping.
    static func reorderProfile(
        in catalog: LanguageProfileCatalog,
        id: UUID,
        direction: LanguageProfileReorderDirection
    ) -> Result<LanguageProfileCatalog, LanguageProfileValidationError> {
        guard let index = catalog.profiles.firstIndex(where: { $0.id == id }) else {
            return .failure(.unknownProfileID(id))
        }
        let target: Int
        switch direction {
        case .up:
            target = index - 1
        case .down:
            target = index + 1
        }
        guard target >= 0, target < catalog.profiles.count else {
            return .failure(.invalidReorderIndex)
        }
        var newProfiles = catalog.profiles
        let moved = newProfiles.remove(at: index)
        newProfiles.insert(moved, at: target)
        return .success(LanguageProfileCatalog(
            profiles: newProfiles,
            activeProfileID: catalog.activeProfileID
        ))
    }

    /// Delete a profile. The final remaining profile cannot be deleted.
    /// When the deleted profile was the Active Profile, the new active
    /// profile is selected according to configured order:
    /// - If the deleted profile was not the last one, the profile that
    ///   followed it becomes active.
    /// - If the deleted profile was the last one, the new last profile
    ///   (the one immediately before the deleted one) becomes active.
    ///
    /// The deleted profile's stored credential override is also removed
    /// from the injected credential store so a later add of a profile
    /// with the same UUID can never accidentally inherit the prior
    /// credential.
    static func deleteProfile(
        from catalog: LanguageProfileCatalog,
        id: UUID,
        credentials: LanguageProfileCredentialStore
    ) -> Result<LanguageProfileCatalog, LanguageProfileValidationError> {
        guard let index = catalog.profiles.firstIndex(where: { $0.id == id }) else {
            return .failure(.unknownProfileID(id))
        }
        if catalog.profiles.count <= 1 {
            return .failure(.cannotDeleteFinalProfile)
        }
        var newProfiles = catalog.profiles
        let removed = newProfiles.remove(at: index)
        let newActiveID: UUID
        if catalog.activeProfileID == id {
            // The deleted profile was active. Pick the successor in
            // configured order: the profile that followed it, or the
            // new last profile when the deleted one was at the end.
            if index < newProfiles.count {
                newActiveID = newProfiles[index].id
            } else {
                newActiveID = newProfiles[newProfiles.count - 1].id
            }
        } else {
            newActiveID = catalog.activeProfileID
        }
        credentials.clearAPIKeyOverride(profileID: removed.id)
        return .success(LanguageProfileCatalog(
            profiles: newProfiles,
            activeProfileID: newActiveID
        ))
    }

    /// Advance the Active Profile to the next profile in configured
    /// order, wrapping to the first profile after the last. This backs
    /// the Switch Language shortcut's one-shot cycle action.
    ///
    /// With exactly one profile in the catalog there is no other
    /// profile to cycle to, so the catalog (and its Active Profile) is
    /// returned unchanged — but the returned `profile` still identifies
    /// that single Active Profile so callers can show cycle-feedback
    /// UI naming it even when selection did not change.
    ///
    /// Falls back to the same no-op behavior if `activeProfileID`
    /// somehow does not identify a member of `profiles` (an invariant
    /// violation `loadCatalog(from:)` never produces), matching
    /// `LanguageProfileCatalog.activeProfile`'s total-accessor fallback.
    static func cycleActiveProfile(
        in catalog: LanguageProfileCatalog
    ) -> (catalog: LanguageProfileCatalog, profile: LanguageProfile) {
        guard catalog.profiles.count > 1,
              let currentIndex = catalog.profiles.firstIndex(where: { $0.id == catalog.activeProfileID }) else {
            return (catalog, catalog.activeProfile)
        }
        let nextIndex = (currentIndex + 1) % catalog.profiles.count
        let nextProfile = catalog.profiles[nextIndex]
        let newCatalog = LanguageProfileCatalog(
            profiles: catalog.profiles,
            activeProfileID: nextProfile.id
        )
        return (newCatalog, nextProfile)
    }

    /// Whether a Switch Language shortcut trigger must be ignored
    /// because a Processing Attempt is currently in flight. A recording
    /// or transcribing session must never have its configuration
    /// mutated mid-flight, so the caller (`AppState`) must skip
    /// `cycleActiveProfile`, skip persistence, and skip the cycle-
    /// feedback overlay entirely — not queue the trigger for later —
    /// whenever this returns `true`.
    static func shouldRejectSwitchLanguageTrigger(isRecording: Bool, isTranscribing: Bool) -> Bool {
        isRecording || isTranscribing
    }

    /// Set the active profile by ID. Rejects an unknown ID so the UI
    /// cannot accidentally leave the catalog in an inconsistent state.
    static func selectProfile(
        in catalog: LanguageProfileCatalog,
        id: UUID
    ) -> Result<LanguageProfileCatalog, LanguageProfileValidationError> {
        guard catalog.profiles.contains(where: { $0.id == id }) else {
            return .failure(.unknownProfileID(id))
        }
        if catalog.activeProfileID == id {
            return .success(catalog)
        }
        return .success(LanguageProfileCatalog(
            profiles: catalog.profiles,
            activeProfileID: id
        ))
    }

    /// Replace an existing profile's persisted fields (name, input
    /// language code, and the four non-secret override strings). The
    /// supplied `updatedProfile` must keep the existing `id`; its
    /// override strings are trimmed, and the same uniqueness invariants
    /// that apply to add/rename are enforced (excluding the profile
    /// being updated from the collision check). Empty override strings
    /// are kept as `""` so they continue to mean "inherit from global".
    static func updateProfile(
        in catalog: LanguageProfileCatalog,
        with updatedProfile: LanguageProfile
    ) -> Result<LanguageProfileCatalog, LanguageProfileValidationError> {
        guard let index = catalog.profiles.firstIndex(where: { $0.id == updatedProfile.id }) else {
            return .failure(.unknownProfileID(updatedProfile.id))
        }
        let trimmedName = updatedProfile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            return .failure(.emptyName)
        }
        let trimmedCode = normalizeInputLanguageCode(updatedProfile.inputLanguageCode)
        for (otherIndex, other) in catalog.profiles.enumerated() where otherIndex != index {
            if other.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                == trimmedName.lowercased() {
                return .failure(.duplicateName(
                    existingProfileID: other.id,
                    existingProfileName: other.name
                ))
            }
            if other.inputLanguageCode == trimmedCode {
                return .failure(.duplicateLanguageCode(
                    existingProfileID: other.id,
                    existingProfileName: other.name
                ))
            }
        }
        let normalized = LanguageProfile(
            id: updatedProfile.id,
            name: trimmedName,
            inputLanguageCode: trimmedCode,
            transcriptionURLOverride: updatedProfile.transcriptionURLOverride
                .trimmingCharacters(in: .whitespacesAndNewlines),
            transcriptionModelOverride: updatedProfile.transcriptionModelOverride
                .trimmingCharacters(in: .whitespacesAndNewlines),
            realtimeModelOverride: updatedProfile.realtimeModelOverride
                .trimmingCharacters(in: .whitespacesAndNewlines),
            postProcessingPromptOverride: updatedProfile.postProcessingPromptOverride
                .trimmingCharacters(in: .whitespacesAndNewlines)
        )
        var newProfiles = catalog.profiles
        newProfiles[index] = normalized
        return .success(LanguageProfileCatalog(
            profiles: newProfiles,
            activeProfileID: catalog.activeProfileID
        ))
    }

    /// Persist a non-empty API-key override for one profile. Empty or
    /// whitespace-only values are rejected so the call site cannot
    /// accidentally clobber a stored credential with empty input; use
    /// `clearAPIKeyOverride(profileID:credentials:)` to clear instead.
    static func setAPIKeyOverride(
        _ value: String,
        for profileID: UUID,
        credentials: LanguageProfileCredentialStore
    ) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        credentials.setAPIKeyOverride(trimmed, profileID: profileID)
    }

    /// Convenience pass-through that forwards to the injected store.
    /// Provided so callers don't have to touch the protocol directly.
    static func clearAPIKeyOverride(
        for profileID: UUID,
        credentials: LanguageProfileCredentialStore
    ) {
        credentials.clearAPIKeyOverride(profileID: profileID)
    }

    /// Compute the effective cleanup prompt that the per-profile editor
    /// "Test" action would send to the post-processing service, without
    /// invoking any live call. The precedence is:
    /// 1. The profile's `postProcessingPromptOverride` when non-empty.
    /// 2. The global `customSystemPrompt` when non-empty.
    /// 3. The injected `builtInDefaultPrompt` (FreeFlow's built-in
    ///    default; the caller passes `PostProcessingService.defaultSystemPrompt`
    ///    in production and an invented synthetic string in tests).
    ///
    /// The built-in default is injected so the helper is dependency-free
    /// and the precedence rule is deterministically testable.
    static func effectiveCleanupPrompt(
        profile: LanguageProfile,
        globalDefaults: LanguageProfileGlobalDefaults,
        builtInDefaultPrompt: String
    ) -> String {
        let trimmedOverride = profile.postProcessingPromptOverride
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedOverride.isEmpty {
            return trimmedOverride
        }
        let trimmedGlobal = globalDefaults.customSystemPrompt
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedGlobal.isEmpty {
            return trimmedGlobal
        }
        return builtInDefaultPrompt
    }

    /// Compute the resolved transcription base URL that the per-profile
    /// editor "Test" action would use. Same precedence as the resolver:
    /// the profile's `transcriptionURLOverride` when non-empty, otherwise
    /// the global `transcriptionBaseURL`.
    static func effectiveTranscriptionBaseURL(
        profile: LanguageProfile,
        globalDefaults: LanguageProfileGlobalDefaults
    ) -> String {
        inherit(profile.transcriptionURLOverride, globalDefaults.transcriptionBaseURL)
    }

    /// Compute the resolved upload transcription model that the
    /// per-profile editor "Test" action would use. Same precedence as
    /// the resolver: profile override when non-empty, otherwise global.
    static func effectiveTranscriptionModel(
        profile: LanguageProfile,
        globalDefaults: LanguageProfileGlobalDefaults
    ) -> String {
        inherit(profile.transcriptionModelOverride, globalDefaults.transcriptionModel)
    }
}