Status: completed
Type: implementation
Category: enhancement
Blocked by: language-profiles/01-active-profile-normal-dictation
Worker: coding-worker-minimax-m3
Claimed by: 
Attempts: 1

# 02: Manage Language Profiles

**What to build:** Add a complete Languages settings experience that lets users manage the ordered catalog and configure optional per-language overrides while seeing inherited behavior clearly.

- [ ] Users can add a Language Profile for any currently unconfigured supported input language.
- [ ] Danish is available as a supported language using its existing `da` hint.
- [ ] Users can rename, reorder, delete, and select Language Profiles.
- [ ] Empty names, duplicate names, duplicate input-language codes, a second Auto-detect profile, and deletion of the final profile are rejected with clear inline feedback.
- [ ] Deleting the Active Profile selects the next available profile according to configured order and removes its stored credential override.
- [ ] Profile duplication is not offered.
- [ ] Users can set or clear transcription URL, credential, upload-model, realtime-model, and ordinary cleanup-prompt overrides.
- [ ] Empty override fields visibly inherit the effective global value without copying it into the profile.
- [ ] Realtime-model copy explains that it applies only to globally enabled live realtime transcription.
- [ ] A profile's effective cleanup prompt can be tested from its editor without changing the existing global prompt test.
- [ ] The old editable global input-language control is removed after migration.
- [ ] Global provider, cleanup prompt, Output Language, vocabulary, context, Edit Mode, and realtime-enabled controls retain their existing meaning.
- [ ] Profile selection and editing remain available during a Processing Attempt, with copy explaining that changes apply to the next attempt.
- [ ] Profile management and prompt-test behavior have deterministic coverage at the approved catalog/resolution seam; live prompt tests are not invoked by automated tests.
- [ ] Repository typechecking and focused tests pass.
