# Issue tracker: Local Markdown

Issues and specs for this repo live as markdown files in `.scratch/`.

## Conventions

- One feature per directory: `.scratch/<feature-slug>/`
- The spec is `.scratch/<feature-slug>/spec.md`
- Implementation issues are one file per ticket at `.scratch/<feature-slug>/issues/<NN>-<slug>.md`, numbered from `01`, never a single combined tickets file. The stable ticket identity is `<feature-slug>/<NN>-<slug>`, not the number alone.
- Every implementation issue starts with the metadata fields `Status:`, `Type:`, `Category:`, `Blocked by:`, `Worker:`, `Claimed by:`, and `Attempts:`. Keep these field names exact so local automation can parse them.
- `Status:` is one of `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `claimed`, `blocked`, `completed`, or `wontfix`.
- `Type:` is `implementation` for build tickets and one of `research`, `prototype`, `grilling`, or `task` for wayfinder decision tickets.
- `Category:` is `bug` or `enhancement`.
- `Blocked by:` is `none` or a comma-separated list of stable ticket identities. A ticket is actionable only when every listed blocker is `completed`.
- `Worker:` is `auto` or an installed `coding-worker-*` agent name. A named worker is an explicit override.
- `Claimed by:` is blank except while an executor owns the ticket. `Attempts:` is a non-negative integer.
- Comments and conversation history append to the bottom of the file under a `## Comments` heading.

## When a skill says "publish to the issue tracker"

Create a new file under `.scratch/<feature-slug>/` (creating the directory if needed).

## When a skill says "fetch the relevant ticket"

Read the file at the referenced path. The user will normally pass the path or issue number directly.

## Wayfinding operations

Used by `/wayfinder`. The map is `.scratch/<effort>/map.md`, with one child file per ticket under `.scratch/<effort>/issues/`. Blocking, claiming, resolution, and frontier selection follow the standard metadata fields above.
