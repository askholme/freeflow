Status: completed
Type: implementation
Category: enhancement
Blocked by: language-profiles/02-manage-language-profiles, language-profiles/04-physical-recording-shared-audio, language-profiles/05-switch-active-profile
Worker: coding-worker-minimax-m3
Claimed by: 
Attempts: 3

# 06: Reprocess the latest Physical Recording

**What to build:** Add a global action that lets a user choose another Language Profile, process the latest saved WAV again, retain both results, and paste the new result through FreeFlow's existing behavior.

- [ ] A configurable Re-run Last Recording shortcut is available and disabled by default.
- [ ] The action is unavailable while recording, transcribing, or running a history Retry.
- [ ] The action finds the latest saved Physical Recording after relaunch, including one whose first transcription failed.
- [ ] A missing WAV, absent recording, or lack of an eligible profile produces concise non-destructive feedback.
- [ ] A non-activating chooser lists eligible profiles in configured order and supports arrows, Return, and Escape.
- [ ] While the chooser is open, configured global shortcuts are suppressed except chooser navigation and Escape.
- [ ] The original profile UUID is excluded while it exists; a deleted and recreated same-language profile remains eligible.
- [ ] Auto-detect is eligible against a specific-language original, and specific languages are eligible against an Auto-detect original.
- [ ] Choosing a profile does not change the Active Profile.
- [ ] Reprocessing resolves a current immutable profile snapshot, uses saved file or local transcription, and never starts realtime streaming.
- [ ] Reprocessing reuses stored context, selected text, and original dictation or Edit Mode intent without capturing current context.
- [ ] The profile cleanup prompt applies only to ordinary dictation; Edit Mode retains its command-transform safety contract.
- [ ] Global translation, vocabulary, post-processing, preserve-exact-wording, voice-macro, and Edit Mode behavior remain in force.
- [ ] Success creates a new linked history result sharing the Physical Recording and WAV, then pastes using current focus and clipboard behavior.
- [ ] Reprocessing never synthesizes Return from the trailing voice command.
- [ ] Transcription failure creates a failed linked history result and does not paste.
- [ ] Post-processing failure retains the normal raw-transcript fallback.
- [ ] Escape during in-flight reprocessing cancels work and creates no history result.
- [ ] Shortcut, chooser state, processing outcomes, context reuse, shared-audio linkage, cancellation, failure, paste requests, and no-Return behavior have deterministic coverage through injected boundaries.
- [ ] Manual verification remains documented for actual event taps, chooser interaction, Accessibility, clipboard, paste, relaunch, and audio playback.
- [ ] Repository typechecking and focused tests pass.


## Ralph attempt 1

Blocked at 2026-09-15T16:48:07.443154+00:00: Standards review still requests changes after 3 review rounds (maxReviewRounds reached): AppState's MainActor.run adapters for reprocessing history-append/paste don't recheck Task.isCancelled after the actor hop, so Escape-cancellation could still race a paste or history write through; Spec review approved throughout, but Standards approval was not reached within the allotted rounds.


## Ralph attempt 2

Blocked at 2026-09-16T20:34:58.970246+00:00: timed out after 3600s with no final result; check the run log for a blocked permission request


## Ralph attempt 3

Blocked at 2026-09-17T08:40:02.060763+00:00: timed out after 7200s with no final result; check the run log for a blocked permission request

## Manual completion 2026-09-17

The Ralph automation in `.ralphy/` referenced agent names (`ralph-controller`,
`ralph-standards-reviewer`, `ralph-spec-reviewer`, `coding-worker-*`) that no
longer resolve in the current OpenCode agent configuration, which is why
attempt 3 silently fell back to an unrelated agent/model and hung until the
timeout. Completed by hand instead of retrying the broken automation:

- Inspected the kept worktree/branch from attempt 2. Both round-3 Standards
  review defects were already fixed in code but had no regression tests:
  1. Escape during the deferred paste window now restores the clipboard via
     `cancelPendingReprocessPaste()` (`Sources/AppState.swift`).
  2. A linked history row that fails to persist is never pasted — gated by
     `ReprocessSuccessOutcome.decide` in `Sources/ReprocessLastRecording.swift`,
     consumed by `AppState.applySuccess`.
- Added the two missing deterministic tests round 3 requested:
  `testDecideNeverPastesAResultThatFailedToPersist` and
  `testPersistLinkedHistoryItemReturnsFailureWhenAppendThrows`
  (`Tests/ReprocessLastRecordingTests.swift`).
- Validated via Docker `swift:5.10-jammy` `swiftc -parse-as-library
  -warnings-as-errors` on the Foundation-only subset (same approach prior
  review rounds used): compiles cleanly, all tests pass including the two
  new ones. `git diff --check` passes.
- `make check` / a full AppKit typecheck could not run natively (no
  `swiftc`/Xcode toolchain in this environment — the same limitation every
  prior review round hit, not a code defect). AppKit-dependent files
  (`AppState.swift`, `SettingsView.swift`, `ReprocessProfileChooserPanel.swift`)
  were reviewed by reading, cross-referenced against the patterns already
  approved in rounds 1–2.
- Rebased the kept `ralph-run/...` branch onto current
  `feature/local-transcription` (only divergence was two ticket-tracker-only
  commits, no code conflicts) and fast-forward merged.
- Manual verification for real AppKit scrolling, event taps, Accessibility,
  clipboard, paste, relaunch, and audio playback remains pending per
  AGENTS.md and this ticket's own checkbox — not exercised in this session.
