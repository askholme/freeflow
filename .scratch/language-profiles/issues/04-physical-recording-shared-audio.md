Status: ready-for-agent
Type: implementation
Category: enhancement
Blocked by: language-profiles/01-active-profile-normal-dictation
Worker: coding-worker-minimax-m3
Claimed by:
Attempts: 0

# 04: Track Physical Recordings and shared audio

**What to build:** Give every saved Physical Recording durable identity and profile metadata, and make pipeline history safely retain one shared WAV across linked Processing Attempts.

- [ ] A new Physical Recording receives stable recording identity and capture time shared by every linked result.
- [ ] History records the original profile identity and each result's processing profile identity, display name, and input-language snapshot without storing endpoint URLs or credentials.
- [ ] Successful and failed initial transcription both retain discoverable Physical Recording metadata when a WAV was saved.
- [ ] Legacy history rows expose deterministic effective recording identity, capture time, and migrated profile identity without destructive rewriting.
- [ ] Profile and recording metadata survive history persistence and app relaunch.
- [ ] The latest Physical Recording is selected by capture time across all retained linked results, including failed initial transcription and an aged-out original row.
- [ ] Linked results can reference one audio filename without copying the WAV.
- [ ] Deleting or trimming one linked result does not return the WAV for deletion while another retained result references it.
- [ ] Removing the final reference returns the audio filename exactly once for deletion.
- [ ] Clearing history returns unique audio filenames.
- [ ] A missing WAV produces a recoverable eligibility error and does not mutate retained history.
- [ ] Public history-store behavior is covered with synthetic entries and an injected in-memory or temporary store.
- [ ] Tests never read real pipeline history or user audio.
- [ ] Repository typechecking and focused tests pass.
