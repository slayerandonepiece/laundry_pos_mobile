---
name: before-clear
description: Verify live state and persist only genuinely durable information (checkpoint / Wiki / native memory) before running /clear. Manually invoked only — never runs automatically. Use when the user asks to run before-clear, check persistence before clearing, or verify it is safe to /clear.
metadata:
  scope: project-local
---

# before-clear

Manually-invoked, project-local procedure. Operates only on the current
working directory's own `.claude/` and `.wiki/`. Never reference or read the
sibling repository (`laundry_pos` from here, or vice versa) — this skill has
no cross-repo awareness by design.

Do not spawn subagents. Do not add or modify hooks, settings.json, or
settings.local.json. Do not modify application source. Do not run `/clear`
yourself — you only report whether it is safe.

## Sequence

### 1. Live state

Run, read-only:
- `git branch --show-current`
- `git status --short`
- `git log -3 --oneline` (only if the task actually needs recent history —
  skip if branch/status already answer the question)

Git is authoritative for implementation/live state. Dirty or uncommitted
files are normal working state, not evidence of anything needing a
checkpoint by themselves.

### 2. Classify

Sort everything relevant from the current conversation into exactly one
bucket — never duplicate a fact across buckets:

- **A. Git/filesystem** — implementation truth. Do nothing with it here.
- **B. CHECKPOINT** — temporary info needed to resume an unfinished task,
  that cannot be reliably reconstructed from git status/diff/log,
  filesystem, Wiki, native memory, or project instructions.
- **C. Wiki** — genuinely durable architecture/business/design/technical
  knowledge (architecture decision, business rule, API contract, reusable
  technical constraint, verified integration behavior).
- **D. Native memory** — durable user preference, tooling governance, or
  workflow rule only. Never architecture, business, or task-state facts.
- **E. Discard** — debugging chatter, intermediate reasoning, obsolete
  observations, anything reconstructable from Git, temporary logs.

Do **not** treat "there are uncommitted files" as a bucket-B fact. Bucket B
only holds things like: what unfinished task the changes belong to, why
work intentionally stopped here, a next action that can't be safely
inferred, a temporary resume decision, or a known temporary constraint
whose meaning isn't visible in Git.

**2a. Ownership check.** Every bucket-B candidate must concern unfinished
state belonging to the CURRENT repository. A fact about another
repository is NEVER bucket B, no matter how non-reconstructable it is —
discard it from this repository's checkpoint. Determine ownership only
from the current repository's own state and the candidate text already
present in conversation; do NOT inspect, read, modify, relocate, or
synchronize with the sibling repository to make this determination or to
act on the result. Git, CHECKPOINT, Wiki, and native-memory operations
stay scoped to the current repository throughout.

### 3. Checkpoint policy

- **Bucket B non-empty** → write/update `.claude/CHECKPOINT.md` with only
  that content, target 80–150 words. Never include: file lists, diff
  stats, commit hashes for their own sake, completed work already visible
  in Git, durable knowledge, or conversation history. It is a resume note,
  not a changelog.
- **Bucket B empty and `.claude/CHECKPOINT.md` exists** → re-read it first.
  Confirm nothing in it is still live, non-reconstructable state (i.e. the
  task it describes is actually done, or its content is now redundant with
  Git/Wiki/memory). If confirmed, delete the file. If anything in it still
  looks live and non-reconstructable, do not delete — instead stop and
  report `NOT SAFE TO /clear: <what's still unresolved in CHECKPOINT.md>`.
- **Bucket B empty and no `.claude/CHECKPOINT.md`** → do nothing. Never
  create the file just to say there's no unfinished work. Its absence
  *is* the "no handoff needed" signal.

### 4. Wiki policy

- **Bucket C empty** → skip this step entirely. Issue zero Wiki reads,
  zero queries, zero writes.
- **Bucket C non-empty**, for each candidate fact:
  1. Verify the fact against its authoritative source (the code, config,
     or design doc it came from) — not from memory of the conversation.
  2. Run the cheapest local/index-first query
     (`/wiki:query --local <question>`, standard or `--quick` depth) to
     check whether equivalent knowledge already exists in this repo's
     `.wiki/`.
  3. If clearly durable and genuinely new or changed: scoped
     `wiki:ingest` → scoped `wiki:compile` targeting only the relevant
     article/category → re-read the resulting article → verify the
     branch index was updated correctly. Never run a full-wiki compile
     for this workflow. Prefer updating an existing article over creating
     a near-duplicate.
  4. If ambiguous, speculative, temporary, or plausibly reconstructable
     from Git/source: do not write anything. Report
     `WIKI CANDIDATE SKIPPED: <short reason>`.

Never promote something merely because it might be useful later.

### 5. Native memory policy

- **Bucket D non-empty** → write via the existing memory-file convention
  (one file per memory + an index entry). Only for durable tooling,
  workflow, or user-preference governance.
- **Bucket D empty** → do nothing.

### 6. Verify persistence

Re-read only files actually changed in steps 3–5 (not the whole Wiki, not
the whole memory directory). Confirm:
- If CHECKPOINT.md was written, it holds only temporary resume state (no
  file lists, no diff stats, no durable knowledge).
- Any Wiki write landed under this repo's own `.wiki/` and nowhere else.
- No duplicate durable knowledge was introduced (the update-vs-create
  check from step 4.3 actually held).
- `git status --short` shows no changes to application source or other
  files beyond what this skill intentionally touched.
- Native memory was not modified unless bucket D explicitly required it.

### 7. Report

Emit exactly:

```
LIVE STATE VERIFIED
CHECKPOINT: updated / removed / unchanged
WIKI: promoted <topic> / WIKI CANDIDATE SKIPPED: <reason> / unchanged
NATIVE MEMORY: updated / unchanged
DISCARDED: <brief categories only>
PERSISTENCE VERIFIED: yes/no
```

Then exactly one of:

```
SAFE TO /clear
```

or

```
NOT SAFE TO /clear: <reason>
```

Do not run `/clear` yourself.
