Status: ready-for-agent
Type: implementation
Category: enhancement
Blocked by: language-profiles/02-manage-language-profiles, language-profiles/04-physical-recording-shared-audio, language-profiles/06-reprocess-latest-recording
Worker: coding-worker-minimax-m3
Claimed by:
Attempts: 0

# 07: Preserve history Retry semantics

**What to build:** Integrate Language Profiles with the existing history Retry action without changing its established row-update, clipboard, or unrelated concurrency behavior.

- [ ] History Retry uses the Language Profile recorded on the selected Processing Attempt.
- [ ] If that profile no longer exists, Retry uses the Active Profile.
- [ ] Retry resolves a current immutable snapshot of the selected profile's settings.
- [ ] Retry preserves the selected row's original dictation or Edit Mode intent and stored context.
- [ ] Retry continues to update the existing history row rather than appending a linked result.
- [ ] Retry continues to copy a successful result without automatically pasting it.
- [ ] Retry retains existing failure presentation and does not destroy the prior usable result.
- [ ] History Retry cannot start while alternate-language reprocessing is active, and alternate-language reprocessing cannot start while a history Retry is active.
- [ ] Existing concurrency between ordinary recording and history Retry remains unchanged.
- [ ] Deterministic orchestration tests cover recorded-profile selection, deleted-profile fallback, immutable resolution, row update, copy-only behavior, failure, and mutual exclusion.
- [ ] Full repository checks and whitespace validation pass after all language-profile tickets are integrated.
- [ ] Required manual macOS verification remains explicitly pending or is documented before merge.
