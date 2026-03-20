# Compounding Skills

A Claude Code skill that makes other skills get better over time. Capture lessons from retros, detect when upstream updates overwrite your customizations, and reapply accumulated learning automatically.

## The Problem

Claude Code skills get auto-updated from upstream repos. Updates are destructive — they overwrite local modifications with no warning or backup. When your team runs retros and identifies improvements to skills, those improvements get lost on the next upstream update. There's no built-in mechanism to detect this or reapply customizations.

## How It Works

**Lessons capture intent, not diffs.** Instead of tracking line-level changes (which break when upstream restructures), compounding-skills records *why* you changed a skill — what was expected, what actually happened, and what the lesson was. This survives upstream restructuring because the intent can be reapplied to any version of the skill.

**Merkle content hashing for drift detection.** Instead of relying on git SHAs (which produce false positives in multi-skill repos), compounding-skills computes a SHA-256 hash over every file in the skill directory. This is precise — it only triggers when actual skill content changes.

**A PreToolUse hook warns you passively.** Before any skill runs, a lightweight hook checks if that skill has drifted since your lessons were last applied. No manual checking required.

## Three Modes

### 1. Retro
Capture a lesson from retrospective feedback and improve a skill.

```
/compounding-skills → Retro

"The brainstorming skill skipped competitive analysis"
→ Records: Expected competitive analysis, Actual: skipped it, Lesson: add as required section
→ Invokes /skill-creator to make the change
→ Records the Merkle hash so it knows the lesson is applied
```

### 2. Update Skills
Check for upstream changes to one or all skills.

```
/compounding-skills → Update Skills

Checked 5 skills:
- brainstorming: updated upstream, 2 lessons need reapplication
- debugging: no changes
- writing-plans: updated upstream, no lessons to reapply
```

### 3. Compound Learning
Reapply historical lessons to skills that were updated upstream.

```
/compounding-skills → Compound Learning

Skill: brainstorming
- L001 "add competitive analysis" — already in upstream version (likely merged). Mark as merged? (y/n)
- L002 "require stakeholder mapping" — reapplying... done
Summary: 1 reapplied, 1 merged upstream, 0 deferred
```

## Installation

### 1. Install the skill

Clone this repo and symlink (or copy) into your Claude Code skills directory:

```bash
git clone https://github.com/mcavopol/compounding-skills.git ~/Code/compounding-skills

# Symlink into Claude Code skills
ln -s ~/Code/compounding-skills ~/.claude/skills/compounding-skills
```

Or copy directly:

```bash
git clone https://github.com/mcavopol/compounding-skills.git ~/Code/compounding-skills
cp -r ~/Code/compounding-skills ~/.claude/skills/compounding-skills
```

### 2. Install the drift detection hook

Copy the hook script:

```bash
cp ~/Code/compounding-skills/hooks/compounding-skills-pretooluse.sh ~/.claude/hooks/
chmod +x ~/.claude/hooks/compounding-skills-pretooluse.sh
```

Add the hook to your Claude Code settings (`~/.claude/settings.json`):

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Skill",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/compounding-skills-pretooluse.sh"
          }
        ]
      }
    ]
  }
}
```

If you already have hooks configured, add the `PreToolUse` entry alongside your existing ones.

### 3. Create the lessons directory

```bash
mkdir -p ~/.claude/compounding-skills-lessons
```

### 4. Verify installation

Run the tests:

```bash
bash ~/.claude/skills/compounding-skills/scripts/test-merkle-hash.sh
bash ~/.claude/skills/compounding-skills/scripts/test-drift-check.sh
```

Then start a Claude Code session and type `/compounding-skills` — you should see the mode menu.

## File Structure

```
~/.claude/skills/compounding-skills/     # The skill itself
  SKILL.md                               # Skill definition
  scripts/
    merkle-hash.sh                       # Compute Merkle hash of a skill directory
    drift-check.sh                       # Check if a skill has drifted

~/.claude/hooks/
  compounding-skills-pretooluse.sh       # PreToolUse hook for passive drift detection

~/.claude/compounding-skills-lessons/    # Created at runtime
  <skill-name>.md                        # Human-owned lessons (append-only)
  <skill-name>.lock.json                 # Machine-owned state (content hash, applied lessons)
```

## How Lessons Are Stored

Lessons are stored as markdown files — human-readable, append-only, and separate from the machine-owned lock state:

```markdown
---
format_version: 1
upstream_source: github.com/org/skills-repo
---

# Lessons: brainstorming

## L001: Add competitive analysis step
- **Retro date:** 2026-03-20
- **Expected:** Skill includes competitive analysis
- **Actual:** Skipped competitive framing entirely
- **Lesson:** Add competitive landscape as a required section
- **Change made:** Added "Competitive Landscape" section after Problem Framing
- **Files touched:** SKILL.md
- **Complexity:** simple
- **PR status:** submitted
- **Applied at content hash:** a1b2c3d4...
```

The lock sidecar (`<skill-name>.lock.json`) tracks operational state:

```json
{
  "format_version": 1,
  "skill_path": "~/.agents/skills/brainstorming/SKILL.md",
  "content_hash": "a1b2c3d4...",
  "hash_captured_at": "2026-03-20T14:00:00Z",
  "lessons_applied": ["L001"],
  "drift_acknowledged_hash": null
}
```

## Dependencies

- **`/skill-creator`** — Retro mode delegates initial skill modification to skill-creator
- **`~/.agents/.skill-lock.json`** — Claude Code's skill manifest, used for upstream source metadata
- **`python3`** — Used by drift-check.sh and the hook for JSON parsing
- **`shasum`** — Used by merkle-hash.sh for SHA-256 hashing (ships with macOS/most Linux)

## Design Decisions

See [docs/design-spec.md](docs/design-spec.md) for the full design spec, including:
- Why Merkle content hashing over git SHAs
- Why intent-based lessons over diffs
- Why human-owned lessons are separated from machine-owned lock state
- Edge case handling (no upstream, plugin-managed, multi-file skills, merged PRs)

## License

MIT
