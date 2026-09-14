Status: ready-for-agent
Type: implementation
Category: enhancement
Blocked by: language-profiles/01-active-profile-normal-dictation, language-profiles/02-manage-language-profiles
Worker: coding-worker-minimax-m3
Claimed by:
Attempts: 0

# 03: Apply profiles to live transcription

**What to build:** Make each live recording consistently use the Language Profile captured at recording start across realtime transcription, upload fallback, local transcription, and cleanup.

- [ ] Recording start captures one immutable resolved Language Profile before starting transcription services.
- [ ] Realtime transcription receives the captured profile's effective endpoint, credential, realtime model, and input-language hint only when the existing global realtime toggle and local-transcription policy allow it.
- [ ] No realtime service is configured or started when realtime is globally disabled.
- [ ] Upload transcription receives the same captured profile when realtime fails or is unavailable.
- [ ] Settings edits during recording or transcription do not alter the captured realtime, upload, language, or prompt configuration.
- [ ] Local transcription continues to follow its global policy, ignores endpoint and model overrides, and still uses the profile's input-language hint and relevant cleanup prompt.
- [ ] Translation remains globally controlled and independent from profile selection.
- [ ] Automated orchestration tests prove realtime gating, shared fallback configuration, immutable capture, local policy, and translation independence using injected services only.
- [ ] No automated test contacts a provider, opens a microphone, or triggers a permission prompt.
- [ ] Repository typechecking and focused tests pass.
