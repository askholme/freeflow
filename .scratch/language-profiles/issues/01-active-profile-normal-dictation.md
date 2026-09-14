Status: completed
Type: implementation
Category: enhancement
Blocked by: none
Worker: coding-worker-minimax-m3
Claimed by: 
Attempts: 2

# 01: Active Profile drives normal dictation

**What to build:** Introduce the minimum complete Language Profile path: migrate the existing input-language setting into one persisted Active Profile, resolve its inherited and overridden values into an immutable snapshot, and use that snapshot for ordinary file transcription and dictation cleanup.

- [ ] Existing users receive one persisted initial Language Profile seeded from their legacy input-language value.
- [ ] Existing global endpoint, credential, upload-model, realtime-model, and cleanup-prompt settings remain inherited defaults, preserving effective behavior after migration.
- [ ] The Active Profile identity is persisted and repaired to the first profile when missing or invalid.
- [ ] Profile names and supported input-language codes are normalized and unique, including at most one Auto-detect profile.
- [ ] At least one Language Profile always remains.
- [ ] Profile API-key values are excluded from encoded profile data and resolved through an injected credential boundary using the existing protected settings mechanism in production.
- [ ] Ordinary file transcription receives the Active Profile's effective endpoint, credential, upload model, and input-language hint.
- [ ] Ordinary dictation cleanup uses the profile prompt override only when non-empty; Edit Mode keeps its existing command-transform prompt.
- [ ] Output Language remains independent from the Active Profile.
- [ ] A Processing Attempt keeps one resolved snapshot even if settings change while it runs.
- [ ] Contradictory partial profile-duplication behavior is removed; profile duplication is unsupported.
- [ ] Deterministic profile catalog, migration, resolution, prompt-scope, translation-independence, and snapshot tests pass without accessing real user settings or providers.
- [ ] Repository typechecking and focused tests pass.


## Ralph attempt 1

Blocked at 2026-09-14T11:54:49.547004+00:00: controller exited 0 without a final success result
