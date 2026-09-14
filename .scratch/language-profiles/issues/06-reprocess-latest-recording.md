Status: ready-for-agent
Type: implementation
Category: enhancement
Blocked by: language-profiles/02-manage-language-profiles, language-profiles/04-physical-recording-shared-audio, language-profiles/05-switch-active-profile
Worker: coding-worker-minimax-m3
Claimed by:
Attempts: 0

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
