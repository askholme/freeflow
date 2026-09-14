# FreeFlow

FreeFlow turns microphone recordings into text through configurable transcription and post-processing behavior.

## Language Profiles

**Language Profile**:
An ordered, named configuration for one unique input language, including optional transcription and ordinary dictation-cleanup overrides. Auto-detect may be represented by at most one profile. A Language Profile does not alter Edit Mode's command-transform contract.
_Avoid_: Language setting, provider profile

**Active Profile**:
The Language Profile selected for the next Physical Recording. Choosing a profile for a separate reprocessing operation does not change it.
_Avoid_: Current language, default language

## Recordings

**Physical Recording**:
One saved audio artifact that may be processed more than once, including when its first Processing Attempt failed.
_Avoid_: Run, retry

**Processing Attempt**:
One transcription and post-processing pass over a Physical Recording using a resolved Language Profile while preserving the recording's original dictation or Edit Mode intent.
_Avoid_: Recording, retry
