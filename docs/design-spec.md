# Compounding Skills — Design Spec

**Date:** 2026-03-20
**Status:** Draft
**Author:** Michael Cavopol + Claude

## Problem

Claude Code skills get auto-updated from upstream repos. Updates are destructive — they overwrite local modifications with no warning or backup. When a team runs retros and identifies improvements to skills, those improvements get lost on the next upstream update. There is no built-in mechanism to detect this or reapply customizations.

## Solution

A Claude Code skill called `compounding-skills` that makes other skills get better over time by capturing lessons from retros, detecting upstream drift, and reapplying accumulated learning.

## Principles

- Skills compound — each lesson makes the skill permanently better
- Lessons capture intent, not diffs — so they survive upstream restructuring
- Lesson content is human-owned; lock state is machine-owned — separated to prevent corruption
- Detection uses Merkle content hashing over the full skill directory, not git SHAs — precise and immune to unrelated repo changes
- Retro mode delegates initial skill modification to `/skill-creator`; Compound Learning applies lessons directly with lightweight editing guidance (no heavyweight eval framework needed for replay)

## Modes

**Direct invocation** (`/compounding-skills`): presents a menu asking which mode.

**Auto-triggered invocations** (from conversation context): skip the menu, go directly to the inferred mode.

### 1. Retro

Capture a lesson from retro feedback and improve a skill.

**Flow:**
1. Identify which skill the feedback applies to (infer from conversation context when possible; if ambiguous, ask — don't guess)
2. Infer expected/actual/lesson from conversation — present for confirmation in structured format:
   > **Skill:** brainstorming / **Expected:** includes competitive analysis / **Actual:** skipped competitive framing / **Lesson:** add competitive landscape as a required section
   - If more than one lesson is inferred, present each individually for confirmation
   - Include a "this isn't quite right, let me explain" escape hatch
3. Assess complexity: simple (added step, wording tweak) or structural (reorganized flow, removed sections)
4. Write/append the lesson entry to `~/.claude/compounding-skills-lessons/<skill-name>.md`
   - If the file doesn't exist, create it with the header (including `format_version: 1`)
   - If it exists, append the new lesson with auto-generated ID and `Applied at content hash: pending`
5. Invoke `/skill-creator` to improve the skill, passing the lesson context
6. After skill-creator completes, update the lesson entry with:
   - **Change made:** what skill-creator actually did
   - **Files touched:** list of files modified
   - **Applied at content hash:** Merkle hash of the skill directory
7. Update the `.lock.json` sidecar with the new content hash and add the lesson ID to `lessons_applied`
8. Ask if the user wants to PR the change upstream (don't assume they do)

**Important:** Steps 6-7 happen immediately after each lesson application, not in a batch.

### 2. Update Skills

Pull upstream changes for one or all skills. Detect drift.

**Flow:**
1. Ask: "One skill or all skills with lessons?"
2. For each skill:
   - Compute Merkle hash of the skill directory
   - Compare to `content_hash` in the skill's `.lock.json` sidecar
   - If match: "No upstream changes detected, skip"
   - If mismatch: show that the skill has been updated and lessons need reapplication
3. For skills with no lessons file: report "Updated upstream, no lessons to reapply"
4. For skills with unapplied lessons: ask "Want to run Compound Learning now?"
   - If yes: transition into Compound Learning for those skills
   - If no: record `drift_acknowledged_hash` in `.lock.json` to suppress repeated prompts until upstream changes again

This mode detects drift only. It does not modify skill files.

### 3. Compound Learning

Reapply historical lessons to skills that were updated upstream.

**Flow:**
1. Ask: "One skill or all skills with unapplied lessons?"
2. For each skill:
   - Read lessons from `~/.claude/compounding-skills-lessons/<skill-name>.md`
   - Identify lessons where `Applied at content hash` doesn't match current skill directory hash (or is "pending")
   - **Auto-detect merged PRs:** For each lesson, check if the lesson's intent is already present in the updated skill. If the upstream version already incorporates the lesson's change, flag it as "likely merged upstream" and ask the user to confirm rather than blindly re-applying
   - Group remaining lessons by complexity:
     - **Simple:** auto-apply, show summary of what was done
     - **Structural:** show lesson intent + relevant section of updated skill, ask for approval
3. For each lesson being applied:
   - Read the current skill files
   - Read the lesson's intent (expected/actual/lesson)
   - Make the minimal edit that addresses the lesson:
     - For simple lessons: add/modify a step, adjust wording, add a guardrail
     - For structural lessons: reorganize sections, adjust flow, add/remove modes
   - Show the diff to the user for confirmation
   - **Update lock and lesson file immediately after each successful application** (not in batch — ensures idempotency on retry)
     - Update `content_hash` in `.lock.json` to current skill directory hash
     - Add lesson ID to `lessons_applied` array
     - Update the lesson's `Applied at content hash`
4. After all lessons are processed:
   - Show summary: X lessons reapplied, Y skipped (merged upstream), Z deferred
5. Ask if the user wants to PR changes upstream

## File Structure

```
~/.claude/compounding-skills-lessons/
  <skill-name>.md              # Human-owned lessons (append-only)
  <skill-name>.lock.json       # Machine-owned state
```

### Lessons File Format (`<skill-name>.md`)

```markdown
---
format_version: 1
upstream_source: github.com/org/repo
---

# Lessons: <skill-name>

## L001: <title>
- **Retro date:** 2026-03-20
- **Expected:** What should have happened
- **Actual:** What actually happened
- **Lesson:** The insight / takeaway
- **Change made:** What was modified in the skill
- **Files touched:** SKILL.md, scripts/analyze.py
- **Complexity:** simple | structural
- **PR status:** pending | submitted | merged | rejected
- **Applied at content hash:** sha256:abc123... | pending
```

Lessons use auto-generated sequential IDs (`L001`, `L002`, etc.) for stable identity. IDs are used for matching between the lessons file and the lock sidecar. Lesson titles are human-readable labels, not identifiers.

### Lock Sidecar Format (`<skill-name>.lock.json`)

```json
{
  "format_version": 1,
  "skill_path": "~/.agents/skills/brainstorming/SKILL.md",
  "content_hash": "sha256:abc123...",
  "hash_captured_at": "2026-03-20T14:00:00Z",
  "lessons_applied": ["L001", "L002"],
  "drift_acknowledged_hash": null
}
```

- `skill_path`: Relative path using `~/` prefix (not absolute) for portability across machines
- `content_hash`: Merkle hash of the skill directory (see Detection Mechanism)
- `lessons_applied`: Array of lesson IDs (not titles) currently applied to the skill
- `drift_acknowledged_hash`: When the user declines reapplication, records the hash they acknowledged. Suppresses repeated prompts until upstream changes again. Set to `null` when lessons are applied or when upstream changes to a new hash.

## Detection Mechanism

### Merkle Content Hash (Primary)

- Computed over the full skill directory: `SHA-256(sorted(filepath + ":" + SHA-256(file_content)) for each file)`
- Hash is computed over raw file bytes, including frontmatter — no whitespace or encoding normalization
- For cross-platform team sharing, normalize line endings to LF before hashing
- Stored in `.lock.json` at lesson-apply time
- Compared at pre-invocation check time and during Update Skills mode
- Precise: only triggers when actual skill content changes (any file in the directory)
- Immune to unrelated repo changes, multi-skill repo false positives, and update mechanism differences

### Why Not `skillFolderHash` from `.skill-lock.json`

The lock file's `skillFolderHash` is a git commit SHA of the upstream repo, not a content hash. Problems:
- Multi-skill repos (e.g., `coreyhaines31/marketingskills` with 5 skills) share one SHA — a change to one skill falsely flags drift in all others
- Unrelated repo changes (README updates, CI config) trigger false positives
- Some skills update without touching the lock file (plugin-managed skills)
- Content hash is the only reliable ground truth

## Hook-Based Drift Detection

A `PreToolUse` hook fires before any `Skill` tool invocation. The hook runs a lightweight check:

1. Extract the skill name from the tool invocation
2. Check if `~/.claude/compounding-skills-lessons/<skill-name>.lock.json` exists — if not, exit (no lessons for this skill)
3. Read `content_hash` and `drift_acknowledged_hash` from the lock sidecar
4. Compute current Merkle hash of the skill directory
5. If current hash matches `content_hash` → no drift, exit
6. If current hash matches `drift_acknowledged_hash` → drift known but user declined, exit
7. Otherwise → inject warning: "The `<skill-name>` skill has been updated upstream since your lessons were last applied. Run `/compounding-skills` in Compound Learning mode to reapply."

Scoped to the invoked skill only. Bulk detection across all skills is handled by Update Skills mode.

## Skill Trigger Description

The skill should trigger on:
- Direct invocation: `/compounding-skills`
- Conversation signals about retros, lessons, and drift — NOT generic "improve this skill" (which belongs to `/skill-creator`)
- Examples: "record a lesson about this skill," "this skill lost my changes," "skill was updated and it's worse now," "check if skills drifted," "run a skill retro," "the brainstorming skill missed X and we should remember that"

When auto-triggered from conversation, skip the mode menu and go directly to the inferred mode (typically Retro).

## Dependencies

- `/skill-creator` — for initial skill modification during Retro mode
- `~/.agents/.skill-lock.json` — for upstream source metadata (source URL, skill path)
- `PreToolUse` hook — for passive drift detection before skill invocations

## Edge Cases

- **Skills with no upstream** (locally authored in `~/.claude/skills/`): Retro mode works normally. Update Skills skips them (no upstream to compare against). Lock sidecar tracks content hash for lesson reapplication only.
- **Plugin-managed skills** (with `pluginName` in lock file): May update outside the normal lock file flow. Merkle content hash detection handles this correctly since it reads files directly.
- **Multi-file skills** (with references/, scripts/ subdirs): Merkle hash covers all files in the skill directory. Lessons track `files_touched` to document which files were modified.
- **PR merged upstream**: Compound Learning auto-detects by checking if the lesson's intent is already present in the updated skill. Flags as "likely merged upstream" and asks user to confirm, rather than relying solely on manual PR status updates.

## Future Considerations

- **Additional modes**: `status` (show all skills with lessons and their drift state), `audit` (review lesson quality), `prune` (clean up obsolete lessons)
- **Team sharing**: Lessons files could be committed to a shared repo so team members benefit from each other's retro insights. Relative paths in `.lock.json` and LF-normalized hashing support this.
