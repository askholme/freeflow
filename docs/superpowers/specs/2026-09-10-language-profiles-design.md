# FreeFlow Language Profiles Design

## Summary

FreeFlow will support an ordered, user-configurable set of language profiles. A profile describes an input language and may override the global transcription endpoint, credentials, upload model, realtime model, and post-processing system prompt. The existing translation setting remains global and independent.

Users can cycle the active profile with a configurable global shortcut. A second configurable shortcut opens a chooser that reprocesses the latest saved recording with another profile, records the attempt as a new run, and pastes the new result.

## Goals

- Support an ordered profile for any subset of FreeFlow's supported input languages.
- Let each profile override transcription URL, API key, upload model, realtime model, and post-processing prompt.
- Preserve current global settings as inherited defaults.
- Cycle the active profile with a global shortcut.
- Reprocess the latest physical recording with a chosen alternative profile.
- Keep the source WAV available across app relaunches and while any history entry still references it.
- Preserve current translation, vocabulary, context, Edit Mode, local-transcription, and post-processing toggles.
- Avoid introducing a new dependency or credential-storage mechanism.

## Non-Goals

- Per-profile post-processing models or fallback models.
- Per-profile translation/output-language settings.
- Per-profile vocabulary, context prompts, Edit Mode settings, or realtime enablement.
- A separate reusable provider-management subsystem.
- Dedicated shortcuts for every profile.
- Changes to provider request formats or supported transcription protocols.
- Changes to permissions, telemetry, signing, releases, or update behavior.

## Current Behavior

`AppState` currently owns one global transcription language, endpoint override, API-key override, upload model, realtime model, and custom post-processing prompt. It constructs `TranscriptionService`, `RealtimeTranscriptionService`, and `PostProcessingService` directly from those values.

The recorder creates a temporary WAV. `AppState.stopAndTranscribe()` copies it into the application-support audio directory and records its filename in `PipelineHistoryItem`. Pipeline history retains up to 20 entries and survives relaunch. Existing history retry logic retranscribes an entry's saved audio using current global settings.

The shortcut core currently recognizes hold-to-talk, tap-to-toggle, and Paste Again roles through one exact-match state machine.

## Profile Model

Add a focused profile model in a production source that can also be compiled into the dependency-free test executable:

```swift
struct LanguageProfile: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var inputLanguageCode: String
    var transcriptionURLOverride: String
    var transcriptionModelOverride: String
    var realtimeModelOverride: String
    var postProcessingPromptOverride: String
}
```

The API-key override is deliberately excluded from the encoded profile. It is loaded and saved separately through `AppSettingsStorage` under an account derived from the stable profile UUID.

Profile rules:

- Names are trimmed, non-empty, and unique using case-insensitive comparison.
- The input language is one of FreeFlow's supported transcription-language options. An empty code continues to mean auto-detect.
- Input-language codes are unique across profiles. This includes the empty auto-detect code, so at most one Auto-detect profile can exist.
- Override strings are trimmed. Empty means inherit the corresponding global setting.
- At least one profile must exist.
- Array order is user-controlled and defines shortcut cycle order.

`AppState` stores `[LanguageProfile]` and `activeLanguageProfileID`. If the selected ID is missing, the first profile becomes active and the repaired selection is persisted.

## Persistence And Migration

Non-secret profile data is JSON-encoded in `UserDefaults`, matching existing structured setting storage. Profile API keys use the existing `AppSettingsStorage` mechanism, which stores values in the owner-only application-support `.settings` file. This feature does not add new Keychain behavior.

On first launch with no profile data, FreeFlow creates one profile named `Default`:

- Its input language is copied from the existing `transcription_language` setting.
- Its endpoint, key, upload model, realtime model, and prompt overrides are empty.
- Existing global settings remain unchanged and therefore resolve exactly as before.

The generated profile ID and active selection are persisted. Existing history rows that predate profiles are interpreted as recordings made with this migrated default profile when profile identity is needed.

Deleting a profile removes its profile-specific API-key entry. Deleting the active profile activates the next profile in display order, wrapping to the previous first profile when necessary. The last remaining profile cannot be deleted.

## Resolved Configuration

Introduce a pure resolver that combines one profile with global settings into an immutable `ResolvedLanguageProfile`. It contains the profile identity and display metadata plus the effective transcription URL, API key, upload model, realtime model, input-language hint, and post-processing prompt.

Resolution rules:

- Empty profile transcription URL inherits the existing resolved global transcription URL.
- Empty profile API key inherits the existing resolved global transcription API key.
- Empty profile upload model inherits the global transcription model.
- Empty profile realtime model inherits the global realtime model.
- Empty profile prompt inherits the global custom system prompt.
- If both profile and global custom prompts are empty, post-processing uses FreeFlow's built-in default prompt.
- Output Language remains a separate global input to post-processing and is not changed by a profile.

The resolved snapshot is captured when recording starts. It is retained in memory for that run so settings edits cannot mix configurations between realtime, upload fallback, and post-processing. API keys in the snapshot are never written to run history or logs.

Local transcription continues to follow the global local-transcription toggle. In local mode, endpoint and transcription-model overrides are not used, but the profile's input-language hint and post-processing prompt still apply to the relevant stages.

## Normal Recording Flow

1. The user starts recording.
2. `AppState` resolves and captures the active profile before starting transcription services.
3. If global realtime streaming is enabled and allowed by local-transcription policy, FreeFlow starts realtime transcription with the captured profile's effective URL, key, realtime model, and input-language hint.
4. If realtime is disabled, no realtime service is configured or started; the profile's realtime-model override is ignored.
5. On stop, FreeFlow saves the WAV as it does today.
6. File transcription uses the captured profile's effective URL, key, upload model, and input-language hint. It remains the fallback if realtime fails.
7. Dictation post-processing uses the profile prompt when non-empty; otherwise it follows the global custom/built-in prompt chain.
8. Global translation, vocabulary, context, post-processing, preserve-exact-wording, voice-macro, and Edit Mode behavior remains in force.
9. The history entry records non-secret profile metadata and recording identity.

Both language shortcuts are ignored while recording or transcribing. The current run is never switched in flight.

## Recording And Attempt Identity

History must distinguish a physical recording from processing attempts. Extend `PipelineHistoryItem` and the inferred Core Data model with optional migration-safe metadata:

- `recordingID`: stable UUID shared by the original run and all alternate-language attempts.
- `recordedAt`: capture timestamp shared by all attempts for that recording.
- `recordingProfileID`: profile selected when the physical recording began.
- `processingProfileID`: profile used for this processing attempt.
- `processingProfileName`: snapshot of the processing profile's display name.
- `processingLanguageCode`: snapshot of its input-language code.

For a new recording, `recordingID` is generated once and both profile IDs are the captured active profile. An alternate-language run reuses recording identity and audio but records its selected processing profile. Legacy rows derive recording identity from their existing entry ID and timestamp and use the migrated default profile identity when the new fields are absent.

Persisting profile name and language snapshots keeps history understandable after a profile is renamed or deleted. Endpoint URLs and API keys are not added to history.

## Alternate-Language Reprocessing

The Re-run Last Recording shortcut is available only while idle. It identifies the newest physical recording by `recordedAt`, considering every retained attempt so the recording remains discoverable even if its original history entry has aged out.

For this action, idle also requires that no existing history Retry is running. A history Retry likewise cannot start while alternate-language reprocessing is active. Existing concurrency between ordinary recording and the pre-existing history Retry feature is otherwise unchanged.

Any recording with a successfully saved WAV is eligible, including one whose first transcription attempt failed.

It opens a compact, keyboard-navigable floating chooser:

- Profiles appear in configured order.
- The recording's original profile UUID is excluded while that profile still exists.
- If the original profile has been deleted, all current profiles are eligible.
- Auto-detect is an eligible alternative to a specific-language profile, and every specific-language profile is eligible for a recording originally made with Auto-detect.
- Arrow keys move selection, Return confirms, and Escape closes without work.
- The chooser reports an unavailable state when there is no retained recording, no eligible alternative profile, or the WAV is missing.
- The chooser uses a non-activating panel, following the existing recording-overlay pattern. Keyboard commands are handled through the shortcut event-monitoring infrastructure rather than by making FreeFlow the active application.
- While the chooser is open, all configured global shortcuts are suppressed except chooser navigation and Escape.

After selection:

1. Resolve and snapshot the selected profile using its current overrides and current global defaults.
2. Reuse the latest retained context belonging to that recording; do not capture a new screenshot, selection, app name, window title, or context-model response.
3. Transcribe the saved WAV through file-upload or local transcription. Reprocessing does not start realtime streaming because the recording is already complete.
4. Apply current global vocabulary, translation, post-processing, preserve-exact-wording, voice-macro, and Edit Mode settings, together with the selected profile's effective prompt.
5. Create a new history entry sharing the recording identity and audio filename.
6. Paste the successful result through the existing clipboard-preservation path. As in the current pipeline, Command-V is sent to whichever control is focused when processing finishes; FreeFlow does not capture, validate, or restore an earlier focus target. Reprocessing never synthesizes Return, even if the new transcript contains the configured trailing "press enter" command.

Choosing a reprocessing profile does not change the Active Profile used for future recordings. A reprocessing failure creates a visible failed history entry referencing the same recording and audio. It does not mutate the prior result and does not paste text. Escape during in-flight reprocessing uses the existing transcription cancellation behavior and does not add a history entry.

## Shared Audio Lifetime

Multiple history entries may reference one WAV. Audio cleanup must therefore become reference-aware:

- Deleting one entry deletes its WAV only if no remaining entry references that filename.
- Trimming history returns only filenames no longer referenced by retained entries.
- Clearing all history returns unique filenames for deletion.
- Failed and successful alternate-language attempts follow the same ownership rules.
- Missing files remain a recoverable user-facing error and do not crash or mutate prior entries.

This keeps one audio copy per physical recording, survives relaunch, and preserves the current 20-entry history limit. Audio is removed only after every referencing history entry is explicitly deleted, cleared, or aged out.

## Shortcut Architecture

Extend the shortcut model with two roles, bindings, and emitted events:

- `switchLanguage`
- `reprocessLastRecording`

Both bindings default to disabled. They are persisted and edited using the same mechanisms as existing shortcuts.

`ShortcutConfiguration`, `ShortcutMatcher`, collision checks, pressed-input accounting, and shortcut-capture UI must include both roles. Exact modifier matching, repeat suppression, event consumption, and existing command-mode modifier rules remain unchanged. Non-dictation events are handled before `DictationShortcutSessionController`, as Paste Again is today, so they cannot alter recording session state.

Switch Language cycles to the next profile in configured order, wraps at the end, persists the active ID, and briefly displays the selected profile name in status/overlay feedback. With one profile, it leaves selection unchanged and reports the current profile. It is ignored while recording or transcribing.

Idle switch feedback uses a brief non-activating overlay showing the newly active profile name.

## Settings And Menu-Bar UI

Add a `Languages` settings tab with an ordered profile list and detail editor. It supports:

- Add, rename, reorder, and delete. Profile duplication is not supported.
- Set active profile.
- Select input-language hint.
- Set or clear transcription URL override.
- Set or clear profile API-key override through `AppSettingsStorage`.
- Set or clear upload-model override.
- Set or clear realtime-model override, with copy explaining that it is used only when global realtime streaming is enabled for live recordings.
- Set or clear post-processing-prompt override.
- Show inherited effective values without copying them into the profile.
- Test the profile's effective post-processing prompt from the profile editor without changing the existing global prompt test.

The existing global provider controls remain defaults. The existing Prompts tab remains the global fallback prompt editor. The existing Output Language control remains global and separate.

The existing global Transcription Language picker is removed after migration. Input language is configured exclusively on Language Profiles; the old global value is used only to seed the initial profile.

Profile prompt overrides apply only to ordinary dictation cleanup. Edit Mode continues to use its dedicated command-transform prompt and safety behavior.

Profile selection and editing remain available while a Processing Attempt is active. The active attempt retains its captured configuration snapshot, and UI copy explains that changes apply to the next attempt.

The existing history Retry action uses the Language Profile recorded on that Processing Attempt. If that profile was deleted, it falls back to the current Active Profile. It preserves current behavior by updating the same history row and copying the result without automatically pasting. Re-run Last Recording remains the distinct action that creates a new linked history entry and pastes after explicitly choosing another language.

The General shortcut editor gains Switch Language and Re-run Last Recording roles. The menu-bar UI shows the active profile and permits direct selection. The floating retry chooser follows existing app visual patterns and does not require a new window architecture.

## Validation And Error Handling

- Reject empty or duplicate profile names in the editor with inline validation.
- Normalize supported language codes through the existing language options.
- Validate non-empty URL overrides using the same HTTP/HTTPS and host requirements as `TranscriptionService` before use; avoid duplicating divergent URL rules.
- Allow model IDs to remain free-form, matching current provider settings.
- Ignore both language shortcuts while FreeFlow is busy rather than queueing a change.
- Treat history Retry and alternate-language reprocessing as mutually exclusive to prevent clipboard and history races; do not otherwise redesign existing recording/retry concurrency.
- Show concise status for missing audio, no recording, no alternative profile, invalid configuration, transcription failure, and cancellation.
- Preserve previous transcripts and active-profile selection when reprocessing fails.
- Continue using raw-transcript fallback when only post-processing fails, consistent with normal runs.

## Privacy And Security

- Store profile API keys only through the existing `AppSettingsStorage`; do not put them in profile JSON, history, errors, exports, or logs.
- Do not log transcripts, prompts, selected text, context, screenshots, API keys, or provider responses through new paths.
- Do not recapture context or screenshots during reprocessing.
- Treat profile prompts and provider responses as untrusted input under the existing post-processing guard behavior.
- Reuse the existing local audio directory and retention policy; do not create an additional cache.
- Because this changes provider request selection, prompt construction, persisted metadata, and audio retention, call those risks out in the eventual pull request.

## Testing

Add dependency-free deterministic tests for:

- Profile encode/decode, normalization, unique-name validation, and positive-count invariant.
- Unique input-language validation, including at most one Auto-detect profile.
- Initial migration from existing transcription-language settings without changing effective endpoint/model/prompt behavior.
- Active-ID repair after profile deletion or corrupt stored selection.
- Inheritance and override resolution for URL, key, upload model, realtime model, language, and prompt.
- Global Output Language remaining independent of profile selection.
- Ordered cycling and wraparound.
- Captured configuration remaining stable when settings change during a run.
- Realtime configuration being used only when global realtime streaming is enabled, and upload fallback using the same captured profile.
- Latest-recording selection across original, retry, deletion, trimming, and legacy history entries.
- Shared audio surviving deletion or trimming while referenced and being deleted after its final reference disappears.
- Alternate-profile eligibility, including a deleted original profile.
- Auto-detect eligibility and UUID-based exclusion of the original profile, including a deleted and recreated same-language profile.
- Reprocessing success, failure, cancellation without a new entry, new-entry behavior on completion, original-context reuse, no paste on transcription failure, and no synthesized Return.
- Mutual exclusion between history Retry and alternate-language reprocessing without changing other existing retry concurrency.
- Profile prompt override taking precedence only when non-empty.
- Both new shortcut roles: exact matching, collision detection, key-repeat suppression, event consumption, busy-state rejection, and no regression to dictation-session behavior.

Use invented metadata, synthetic temporary audio fixtures, and mocked or local service boundaries. Tests must not contact live providers or contain real audio, transcripts, prompts, context, filesystem paths, or credentials. Add any new pure production sources required by tests to `TEST_PRODUCTION_SOURCES` in the Makefile.

Run:

```bash
make check
git diff --check
```

Manual verification is required before merge for:

- Adding, editing, reordering, deleting, and persisting profiles.
- Testing a profile-specific effective prompt independently from the global prompt test.
- Profile API-key inheritance and override behavior without exposing key contents.
- Language-cycle shortcut feedback and wraparound.
- Retry chooser keyboard navigation and Escape behavior.
- Successful alternate-language reprocessing and paste.
- Retry after app relaunch.
- Missing-audio and no-alternative-profile states.
- Shared-audio playback and deletion across linked history entries.
- Realtime disabled, realtime enabled, realtime fallback, and local-transcription behavior.
- Global translation remaining independent of profile selection.

## Expected Code Areas

The implementation is expected to touch these focused areas:

- New language-profile model/resolver source and tests.
- `AppState.swift` for persistence, captured configuration, orchestration, migration, retry, and status behavior.
- `TranscriptionService.swift` only as needed to share URL validation or expose testable configuration boundaries.
- `PostProcessingService.swift` call sites for effective prompt selection; post-processing model selection remains global.
- `PipelineHistoryItem.swift` and `PipelineHistoryStore.swift` for recording identity, profile snapshots, and shared-audio cleanup.
- `ShortcutCore/ShortcutModels.swift`, `ShortcutMatcher.swift`, `HotkeyManager.swift`, and shortcut tests.
- `ShortcutComponents.swift` and `SettingsView.swift` for new roles and language-profile management.
- `MenuBarView.swift` and a small chooser view for active-profile selection and alternate-language choice.
- `Makefile` only to include new testable production sources in the test executable.

No architecture migration to Swift Package Manager or Xcode is required.
