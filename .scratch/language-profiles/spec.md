Status: ready-for-agent

# Language Profiles

## Problem Statement

FreeFlow currently has one global input-language and transcription configuration. A multilingual user must edit settings whenever they switch spoken languages, cannot give each input language its own transcription endpoint or cleanup prompt, and cannot quickly recover when the latest Physical Recording was processed with the wrong language.

The app also needs to retain enough recording identity and audio ownership information to process one Physical Recording more than once without duplicating sensitive audio or deleting a shared WAV while a Processing Attempt still references it.

## Solution

Introduce an ordered catalog of Language Profiles. Each Language Profile represents one unique supported input language and may override the global transcription URL, API key, upload model, realtime model, and ordinary dictation-cleanup prompt. Empty overrides inherit the existing global values. Translation remains a separate global setting.

Users select an Active Profile for the next Physical Recording. A configurable shortcut cycles the Active Profile and displays brief non-activating feedback. Another configurable shortcut opens a non-activating, keyboard-navigable chooser that processes the latest saved Physical Recording with another Language Profile, creates a linked history result, and pastes it using FreeFlow's existing focus and clipboard behavior.

## User Stories

1. As a multilingual user, I want to configure several supported input languages, so that I can dictate in each without repeatedly editing global settings.
2. As a Danish speaker, I want Danish to be available as a profile language, so that I can provide the `da` transcription hint.
3. As a user who relies on provider detection, I want one Auto-detect profile, so that I can retain today's automatic-language behavior.
4. As a user, I want each configured input language to be unique, so that cycling profiles has unambiguous language semantics.
5. As a user, I want to name each Language Profile, so that I can recognize it in Settings, the menu bar, overlays, and history.
6. As a user, I want to reorder Language Profiles, so that the cycle shortcut follows my preferred sequence.
7. As a user, I want to add and delete Language Profiles, so that the catalog reflects the languages I currently use.
8. As a user, I want FreeFlow to prevent deletion of my final Language Profile, so that the app always has a valid input configuration.
9. As a user, I want deleting the Active Profile to select a nearby remaining profile, so that future recording remains predictable.
10. As an existing user, I want my current transcription language migrated into an initial profile, so that an upgrade does not change my effective behavior.
11. As an existing user, I want current provider, model, key, and prompt settings to remain global defaults, so that migration does not duplicate or unexpectedly alter them.
12. As a user, I want the old global input-language control removed after migration, so that there is only one source of truth for input language.
13. As a user, I want a Language Profile to override the transcription URL, so that different languages can use different compatible endpoints.
14. As a user, I want a Language Profile to override the transcription API key, so that language-specific endpoints can use separate credentials.
15. As a user, I want profile credentials stored through FreeFlow's existing protected settings mechanism, so that the feature does not introduce a second credential system.
16. As a user, I want a Language Profile to override the upload transcription model, so that each language can use an appropriate speech model.
17. As a user, I want a Language Profile to override the realtime model, so that live transcription can use a language-appropriate realtime model.
18. As a user, I want realtime overrides ignored when realtime streaming is disabled, so that configuring profiles does not enable extra network transmission.
19. As a user, I want completed-audio reprocessing to avoid realtime streaming, so that saved WAVs follow the normal file-transcription path.
20. As a user, I want a Language Profile to override the ordinary cleanup prompt, so that language-specific grammar and formatting instructions can be applied.
21. As a user, I want an empty profile prompt to inherit the global custom or built-in prompt, so that I only configure exceptions.
22. As an Edit Mode user, I want profile prompts not to replace the command-transform prompt, so that Edit Mode keeps its distinct safety contract.
23. As a user, I want to test a profile's effective cleanup prompt in its editor, so that I know which inherited and overridden instructions will run.
24. As a user, I want the existing global prompt test to remain global, so that its meaning does not silently change with the Active Profile.
25. As a user, I want translation to remain independently configurable, so that selecting an input language does not force an output language.
26. As a user, I want vocabulary, context, post-processing, preserve-exact-wording, voice macros, and Edit Mode to retain their current global behavior, so that profiles change only language-specific concerns.
27. As a user, I want profile changes during a Processing Attempt to apply only to future attempts, so that an in-flight request never mixes old and new settings.
28. As a user, I want to cycle the Active Profile with a configurable global shortcut, so that I can switch languages without opening Settings.
29. As a user, I want profile cycling to follow configured order and wrap at the end, so that repeated shortcut presses are predictable.
30. As a user, I want brief non-activating feedback after cycling, so that I can confirm the newly Active Profile without losing focus.
31. As a user, I want language shortcuts ignored while recording or transcribing, so that the current Processing Attempt cannot change configuration mid-flight.
32. As a user, I want both new shortcuts disabled by default, so that upgrading does not claim unexpected global key combinations.
33. As a user, I want new shortcuts to use FreeFlow's exact matching and collision rules, so that existing shortcut safety is preserved.
34. As a user, I want a shortcut to process my latest saved Physical Recording with another profile, so that I can correct a wrong-language result quickly.
35. As a user, I want the alternate-language shortcut to work after relaunch, so that recovery is not limited to one app session.
36. As a user, I want a saved WAV with a failed first transcription to remain eligible, so that another endpoint or language may recover it.
37. As a user, I want a non-activating profile chooser, so that opening it does not itself move focus away from my current application.
38. As a keyboard user, I want arrows, Return, and Escape to operate the chooser, so that I do not need the mouse.
39. As a user, I want configured shortcuts suppressed while the chooser is open, so that another action cannot mutate state underneath a pending choice.
40. As a user, I want the original profile UUID excluded from the chooser, so that the action selects a distinct profile.
41. As a user, I want Auto-detect to be eligible as an alternative to a specific language and vice versa, so that I can recover from a bad forced hint or bad detection.
42. As a user, I want a recreated same-language profile with a new UUID to remain eligible, so that profile identity stays simple and endpoint changes can be tried.
43. As a user, I want choosing a reprocessing profile not to change the Active Profile, so that one correction does not alter future recordings.
44. As a user, I want alternate processing to reuse the original saved context, so that FreeFlow does not capture a new screenshot, selection, app, or window.
45. As an Edit Mode user, I want alternate processing to preserve the original selected text and Edit Mode intent, so that it repeats the intended operation rather than becoming dictation.
46. As a user, I want successful alternate processing recorded as a new linked history result, so that the previous result remains available.
47. As a user, I want successful alternate processing pasted through the existing paste pipeline, so that clipboard preservation remains consistent.
48. As a user, I want reprocessing to retain today's focus behavior, so that FreeFlow pastes into whichever control is focused when processing finishes without adding focus restoration.
49. As a user, I want alternate processing never to synthesize Return, so that a delayed correction cannot unexpectedly submit content.
50. As a user, I want transcription failure during alternate processing to create a visible failed history result without pasting, so that failure is inspectable and non-destructive.
51. As a user, I want post-processing failure to preserve the normal raw-transcript fallback, so that usable transcription is not lost.
52. As a user, I want cancelling alternate processing to add no history result, so that deliberate cancellation leaves history clean.
53. As a user, I want history Retry and alternate processing to be mutually exclusive, so that their clipboard and history writes cannot race.
54. As a user, I want ordinary recording and existing history Retry concurrency otherwise unchanged, so that this feature does not redesign unrelated behavior.
55. As a user, I want existing history Retry to reuse the profile recorded on that result, so that Retry means trying the same configuration again.
56. As a user, I want history Retry to fall back to the Active Profile if its recorded profile was deleted, so that old entries remain actionable.
57. As a user, I want history Retry to keep updating its existing row and copying without pasting, so that established Retry behavior remains unchanged.
58. As a user, I want linked history results to share one WAV, so that alternate processing does not duplicate sensitive audio.
59. As a user, I want deleting one linked result to preserve the WAV while another result references it, so that retained results remain playable and retryable.
60. As a user, I want a WAV deleted after its final history reference disappears, so that audio is not retained unnecessarily.
61. As a user, I want clearing history to delete each shared WAV once, so that cleanup is complete and deterministic.
62. As a user, I want history trimming to retain shared WAVs still referenced by surviving results, so that the 20-entry limit does not break retained entries.
63. As a user, I want missing audio reported without mutating prior history, so that filesystem inconsistencies fail safely.
64. As a privacy-conscious user, I want profile API keys excluded from profile JSON, history, exports, errors, and logs, so that credentials do not leak.
65. As a privacy-conscious user, I want alternate processing to avoid new context capture, so that retrying audio does not collect unrelated current-screen data.
66. As a maintainer, I want historical profile name and language snapshots, so that history remains understandable after profiles are renamed or deleted.
67. As a maintainer, I want legacy history to have deterministic effective recording and profile identities, so that migration does not require destructive rewriting.
68. As a maintainer, I want no new dependencies or project-system migration, so that FreeFlow remains a direct `swiftc` and Make application.

## Implementation Decisions

- Model a Language Profile as a stable identity, display name, one supported input-language code, and optional non-secret overrides. Store its API-key override separately by profile identity.
- Require unique trimmed names and unique input-language codes among current profiles. Permit at most one Auto-detect profile and always retain at least one profile.
- Persist ordered profiles and Active Profile identity as structured user defaults. Use the existing protected application-settings storage for profile API-key overrides.
- Seed one initial profile from the legacy transcription-language value. Keep existing endpoint, credential, model, and prompt settings as inherited global defaults.
- Resolve a Language Profile and global defaults into one immutable runtime snapshot before a Processing Attempt begins. Never persist or log the resolved API key.
- Use the captured snapshot for realtime transcription, upload fallback, and ordinary post-processing within a live recording.
- Start realtime transcription only when the existing global realtime toggle and local-transcription policy allow it. Never start realtime for a completed WAV.
- Keep Output Language and all other existing pipeline options global and independent from profile selection.
- Apply profile prompt overrides only to ordinary dictation cleanup. Preserve the dedicated Edit Mode command-transform prompt.
- Represent each Physical Recording with stable recording identity and capture time shared by linked history results. Record original and processing profile identities plus non-secret display snapshots.
- Interpret missing legacy metadata deterministically from existing history identity, timestamp, and the migrated initial profile.
- Select the latest Physical Recording by capture time across retained linked results, including failed first attempts.
- Reuse one audio filename across linked history results. Make deletion, trimming, and clearing reference-aware before deleting audio.
- Compare alternate-profile eligibility by stable profile UUID. A deleted and recreated profile is a distinct choice even when its language code matches historical data.
- Preserve the original dictation or Edit Mode intent and stored context during alternate processing. Do not recapture current context.
- Create a new linked history result for completed alternate processing. Create a failed result for transcription failure, but no result for cancellation.
- Preserve current paste focus behavior and clipboard handling. Alternate processing must suppress trailing Return synthesis.
- Keep existing history Retry semantics: use its recorded profile when available, update the same row, and copy without pasting.
- Treat active history Retry and alternate processing as mutually exclusive. Do not otherwise change existing recording/retry concurrency.
- Extend the exact-match shortcut domain with Switch Language and Re-run Last Recording roles, both disabled by default and isolated from dictation-session state.
- Present chooser and cycle feedback through non-activating UI. Route chooser keyboard commands through global input handling and suppress unrelated configured shortcuts while it is open.
- Add a Languages settings area for adding, renaming, ordering, deleting, selecting, configuring, and testing profiles. Do not support profile duplication.
- Remove the editable global input-language picker after migration while retaining global provider and prompt controls as inherited defaults.
- Keep profile editing available during processing; immutable snapshots make those changes effective on the next attempt.
- Preserve the direct compiler and Make architecture without adding dependencies.

## Testing Decisions

- Test externally observable contracts through four seams: Language Profile catalog/resolution, pipeline history ownership, Processing Attempt orchestration, and shortcut reduction.
- Keep domain tests isolated from real user defaults and protected settings by injecting configuration and credential operations. Tests must never read the real application-support settings file.
- Test profile encoding without credentials, migration, validation, invariants, ordering, cycling, deletion selection, active-ID repair, inheritance, overrides, immutable snapshots, prompt scope, and translation independence through the profile catalog/resolver seam.
- Test profile and recording metadata round-trips, deterministic legacy identities, latest-recording selection, shared-audio retention, final-reference deletion, unique clear results, and trimming through an injectable in-memory history store.
- Introduce one narrow async Processing Attempt coordinator with injected transcription, post-processing, history, context, and paste operations. Test complete outcomes rather than private branches.
- Test realtime gating, consistent upload fallback snapshots, completed-WAV behavior, context reuse, Edit Mode intent, success, transcription failure, raw fallback, cancellation, no Return synthesis, active-profile stability, and retry mutual exclusion through that coordinator.
- Extend the existing shortcut reducer tests for both one-shot actions, disabled defaults, exact matching, repeat suppression, collision detection, event consumption, pressed-input accounting, chooser suppression, and dictation-session isolation.
- Use existing reducer tests, async cancellation gates, temporary-filesystem fixtures, isolated defaults suites, and pure transformation tests as prior art.
- Add only focused production modules to the dependency-free test executable's explicit production-source list.
- Use invented synthetic values and local or mocked operations. Automated tests must not call providers, trigger permissions, or contain real audio, transcripts, prompts, context, screenshots, filesystem paths, or credentials.
- Run the full repository check and whitespace validation before handoff.
- Manually verify profile editing and persistence, inherited-value presentation, profile prompt testing, protected API-key behavior, cycle feedback, global shortcut capture, chooser keyboard navigation and suppression, Escape, microphone capture, realtime enabled/disabled/fallback behavior, local transcription, clipboard preservation, paste behavior, absence of synthesized Return, relaunch retry, shared-audio playback/deletion, and missing-WAV presentation.

## Out of Scope

- Per-profile post-processing or fallback models.
- Per-profile translation, vocabulary, context prompts, Edit Mode settings, or realtime enablement.
- Arbitrary or custom input-language codes outside FreeFlow's supported list.
- Multiple current profiles for one input language.
- Profile duplication.
- Dedicated shortcuts for individual profiles.
- A reusable provider-management subsystem.
- Focus capture, validation, or restoration after processing.
- Provider protocol or request-format changes.
- New credential-storage mechanisms.
- New dependencies, Swift Package Manager, or an Xcode project.
- Telemetry, permissions, signing, release, update, or workflow changes.
- Redesigning existing concurrency between ordinary recording and history Retry.

## Further Notes

- Danish is already present in FreeFlow's supported input-language list as `da`.
- The feature changes provider selection, prompt construction, persisted metadata, shortcuts, paste behavior, and sensitive audio retention. These risks must be called out in review and in any eventual pull request.
- Actual microphone, realtime, global-shortcut, Accessibility, clipboard, paste, and retained-audio behavior requires documented manual macOS verification before merge.
- The current worktree contains partial implementation left by a cancelled worker. That partial code is not evidence that the specification is complete and includes profile-duplication behavior that contradicts this specification.
