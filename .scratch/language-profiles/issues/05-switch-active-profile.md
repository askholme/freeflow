Status: completed
Type: implementation
Category: enhancement
Blocked by: language-profiles/01-active-profile-normal-dictation, language-profiles/02-manage-language-profiles
Worker: coding-worker-minimax-m3
Claimed by: 
Attempts: 2

# 05: Switch the Active Profile globally

**What to build:** Let users select or cycle the Active Profile without opening Settings, while preserving FreeFlow's exact global-shortcut behavior and current recording state.

- [ ] The menu-bar interface shows the Active Profile and permits direct selection.
- [ ] A configurable Switch Language shortcut is available and disabled by default.
- [ ] Each shortcut activation advances through configured profile order and wraps at the end.
- [ ] With one profile, activation leaves selection unchanged and reports that profile.
- [ ] Successful cycling persists the new Active Profile for the next Physical Recording.
- [ ] Cycling while recording or transcribing is ignored rather than queued.
- [ ] A brief non-activating overlay displays the selected profile name without stealing application focus.
- [ ] The shortcut participates in exact matching, collision validation, repeat suppression, event consumption, and pressed-input accounting.
- [ ] The new shortcut event cannot start, stop, or otherwise mutate a dictation session.
- [ ] Existing shortcuts retain their behavior and matching rules.
- [ ] Deterministic reducer and action tests cover disabled defaults, cycling, wraparound, busy rejection, collisions, and dictation-session isolation.
- [ ] Repository typechecking and focused tests pass.


## Ralph attempt 1

Blocked at 2026-09-14T18:47:59.676131+00:00: controller exited 1 without a final success result
