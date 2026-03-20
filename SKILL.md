---
name: compounding-skills
description: >-
  Capture retro lessons for skills and reapply them after upstream updates.
  Use when users discuss skill retros, want to record a lesson about skill behavior,
  need to check if upstream skill updates overwrote their customizations,
  or want to reapply historical improvements to updated skills.
  Also triggers on: "this skill lost my changes," "skill was updated and it's worse now,"
  "record this as a lesson for [skill-name]," "check if skills drifted,"
  "run a skill retro," "the [skill-name] missed X and we should remember that."
---

# Compounding Skills

Make skills get better over time. Capture lessons from retros, detect upstream drift, and reapply accumulated learning after upstream updates.

## Entry Point

**Direct invocation** (`/compounding-skills`): Present the mode menu:
> Which mode?
> 1. **Retro** — Capture a lesson from feedback and improve a skill
> 2. **Update Skills** — Check for upstream changes to one or all skills
> 3. **Compound Learning** — Reapply historical lessons to updated skills

**Auto-triggered** (from conversation context about skill underperformance): Skip the menu and go directly to the inferred mode. Signals like "this skill missed X" → Retro. "My skill changes got overwritten" → Update Skills / Compound Learning.

## Conventions

- **Lessons directory:** `~/.claude/compounding-skills-lessons/`
- **Merkle hash script:** `~/.claude/skills/compounding-skills/scripts/merkle-hash.sh`
- **Drift check script:** `~/.claude/skills/compounding-skills/scripts/drift-check.sh`
- **Lock file metadata:** `~/.agents/.skill-lock.json` (for upstream source info)

## Mode 1: Retro

Capture a lesson from retro feedback and improve a skill.

### Flow

1. **Identify the skill.** Infer from conversation context. If ambiguous (multiple skills discussed, unclear reference), ask — don't guess.

2. **Infer the lesson.** Extract expected/actual/lesson from the conversation. Present for confirmation in structured format:

   > **Skill:** brainstorming
   > **Expected:** includes competitive analysis step
   > **Actual:** skipped competitive framing entirely
   > **Lesson:** add competitive landscape as a required section after problem framing

   - If more than one lesson is inferred, present each individually for confirmation
   - If the user says "this isn't quite right," let them correct without starting over

3. **Assess complexity.** Ask: "Is this a simple change (added step, wording tweak) or structural (reorganized flow, removed/added sections)?"
   - Default to `structural` if unclear

4. **Write the lesson.** Create or append to `~/.claude/compounding-skills-lessons/<skill-name>.md`:

   If the file doesn't exist, create it with this header:
   ```
   ---
   format_version: 1
   upstream_source: <from .skill-lock.json sourceUrl field>
   ---

   # Lessons: <skill-name>
   ```

   Append the lesson (auto-increment the ID based on existing lessons):
   ```
   ## L001: <descriptive title>
   - **Retro date:** <today's date>
   - **Expected:** <what should have happened>
   - **Actual:** <what actually happened>
   - **Lesson:** <the takeaway>
   - **Change made:** pending
   - **Files touched:** pending
   - **Complexity:** simple | structural
   - **PR status:** pending
   - **Applied at content hash:** pending
   ```

5. **Invoke `/skill-creator`** to improve the skill, passing the lesson context:
   > "Improve the `<skill-name>` skill. Here's the context: [expected], [actual], [lesson]. Make the minimal change that addresses this lesson."

6. **Update the lesson entry** after skill-creator completes:
   - Set **Change made** to what was actually modified
   - Set **Files touched** to the list of files that changed
   - Compute Merkle hash: `bash ~/.claude/skills/compounding-skills/scripts/merkle-hash.sh <skill-dir>`
   - Set **Applied at content hash** to the computed hash

7. **Update the lock sidecar** (`~/.claude/compounding-skills-lessons/<skill-name>.lock.json`):

   If the file doesn't exist, create it:
   ```json
   {
     "format_version": 1,
     "skill_path": "<relative path with ~/ prefix>",
     "content_hash": "<merkle hash>",
     "hash_captured_at": "<ISO 8601 timestamp>",
     "lessons_applied": ["L001"],
     "drift_acknowledged_hash": null
   }
   ```

   If it exists, update `content_hash`, `hash_captured_at`, and append the lesson ID to `lessons_applied`.

8. **Ask about PR.** "Want to PR this change to the upstream repo? (The source is `<upstream_source>`.)" Don't assume they do.

## Mode 2: Update Skills

Detect upstream drift for one or all skills.

### Flow

1. **Ask scope.** "Check one skill or all skills?"

2. **For skills with lessons** (have a `.lock.json` in `~/.claude/compounding-skills-lessons/`):
   - Resolve the skill directory from `skill_path` in the lock file (expand `~`)
   - Compute current Merkle hash: `bash ~/.claude/skills/compounding-skills/scripts/merkle-hash.sh <skill-dir>`
   - Compare to `content_hash` in the lock sidecar:
     - **Match:** "No upstream changes detected for `<skill-name>`, skipping."
     - **Mismatch:** "The `<skill-name>` skill has been updated upstream. X lessons need reapplication."

3. **For skills without lessons** (no `.lock.json`):
   - If checking "all": scan `~/.agents/.skill-lock.json` for skills where `updatedAt` differs from `installedAt` (indicates an upstream update has occurred). Report: "Updated upstream, no lessons to reapply."
   - If checking a single skill: report "No lessons recorded for this skill."

4. **For skills with drift and lessons:**
   - Ask: "Want to run Compound Learning now to reapply lessons?"
   - If yes: transition to Compound Learning mode for those skills
   - If no: update `drift_acknowledged_hash` in the lock sidecar to the current Merkle hash. This suppresses the PreToolUse hook warning until the next upstream change.

5. **Summary:** "Checked X skills. Y up to date. Z have upstream changes (W with lessons to reapply)."

## Mode 3: Compound Learning

Reapply historical lessons to skills that were updated upstream.

### Flow

1. **Ask scope.** "Reapply lessons for one skill or all skills with unapplied lessons?"

2. **For each skill, read its lessons** from `~/.claude/compounding-skills-lessons/<skill-name>.md`:
   - Parse all lesson entries
   - Compute current Merkle hash of the skill directory
   - Identify lessons where `Applied at content hash` doesn't match the current hash (or is "pending")

3. **Auto-detect merged PRs.** For each unapplied lesson:
   - Read the current skill files
   - Check if the lesson's intent (the **Lesson** and **Change made** fields) is already present in the current version
   - If the upstream version already incorporates the change, flag it:
     > "Lesson L001 ('add competitive analysis step') appears to already be in the upstream version. Mark as merged? (y/n)"
   - If confirmed: set **PR status** to `merged`, set **Applied at content hash** to current hash, skip reapplication

4. **Group remaining lessons by complexity:**
   - **Simple** (`complexity: simple`): auto-apply and show a summary
   - **Structural** (`complexity: structural`): show the lesson intent + the relevant section of the current skill, ask for approval before applying

5. **Apply each lesson.** For each lesson being applied:
   - Read the current skill files
   - Read the lesson's intent: **Expected**, **Actual**, **Lesson**, and previous **Change made**
   - Make the minimal edit that addresses the lesson:
     - Simple: add/modify a step, adjust wording, add a guardrail
     - Structural: reorganize sections, adjust flow, add/remove content
   - Show the diff to the user for confirmation (even for simple — just don't block on it)
   - **Immediately after each successful application:**
     - Update the lesson's **Applied at content hash** to the new Merkle hash
     - Update the lesson's **Files touched** if different from original
     - Update `content_hash` and `hash_captured_at` in the lock sidecar
     - Add the lesson ID to `lessons_applied` in the lock sidecar
     - Clear `drift_acknowledged_hash` (set to `null`)
   - This per-lesson update ensures idempotency: if the process is interrupted, a retry correctly skips already-applied lessons.

6. **Summary:** "X lessons reapplied, Y skipped (merged upstream), Z deferred."

7. **Ask about PR.** "Want to PR these changes to the upstream repo?"

## Edge Cases

- **Skills with no upstream** (locally authored): Retro mode works normally. Update Skills skips them. Lock sidecar tracks content hash for lesson reapplication only.
- **Plugin-managed skills** (installed via marketplace): May update outside the normal flow. Merkle hash detection handles this since it reads files directly.
- **Multi-file skills:** Merkle hash covers all files. Lessons track `files_touched` to document which files were modified.
- **PR merged upstream:** Compound Learning auto-detects by checking if the lesson's intent is already present in the updated skill. Flags as "likely merged" and asks user to confirm.
- **Skill name resolution:** For qualified names like `superpowers:brainstorming`, use only the part after the colon. For skills in the lock file, match by the skill directory name.
- **Lock sidecar missing or corrupted:** If `.lock.json` is missing, compute current Merkle hash and check each lesson's `Applied at content hash`. If a lesson's hash matches the current file, it's applied. If no match, mark all as unapplied and prompt the user. If JSON is invalid, warn the user and offer to rebuild.

## References

- **Spec:** `docs/superpowers/specs/2026-03-20-compounding-skills-design.md`
- **Skill Creator:** `/skill-creator` — used in Retro mode for initial skill modification
- **Lock file:** `~/.agents/.skill-lock.json` — upstream source metadata per skill
