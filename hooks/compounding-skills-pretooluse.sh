#!/usr/bin/env bash
# compounding-skills-pretooluse.sh — PreToolUse hook for drift detection
# Runs before any Skill tool invocation to check for unapplied lessons.
# Input: JSON on stdin with tool_name and tool_input fields
set -euo pipefail

# Read hook input from stdin
INPUT=$(cat)

# Only act on Skill tool invocations
TOOL_NAME=$(echo "$INPUT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null || echo "")
if [[ "$TOOL_NAME" != "Skill" ]]; then
  exit 0
fi

# Extract skill name from tool input
SKILL_NAME=$(echo "$INPUT" | python3 -c "
import json, sys
data = json.load(sys.stdin)
skill = data.get('tool_input', {}).get('skill', '')
# Handle qualified names like 'superpowers:brainstorming' -> 'brainstorming'
if ':' in skill:
    skill = skill.split(':')[-1]
print(skill)
" 2>/dev/null || echo "")

if [[ -z "$SKILL_NAME" ]]; then
  exit 0
fi

LESSONS_DIR="$HOME/.claude/compounding-skills-lessons"
SCRIPTS_DIR="$HOME/.claude/skills/compounding-skills/scripts"

# Check if we have lessons for this skill
if [[ ! -f "$LESSONS_DIR/$SKILL_NAME.lock.json" ]]; then
  exit 0
fi

# Resolve skill directory path from lock file
SKILL_PATH=$(python3 -c "
import json, os
lock = json.load(open('$LESSONS_DIR/$SKILL_NAME.lock.json'))
path = lock.get('skill_path', '')
# Expand ~ to home directory
path = os.path.expanduser(path)
# Get directory from file path
print(os.path.dirname(path))
" 2>/dev/null || echo "")

if [[ -z "$SKILL_PATH" || ! -d "$SKILL_PATH" ]]; then
  exit 0
fi

# Run drift check — capture output, exit code 1 means drift detected
DRIFT_OUTPUT=$("$SCRIPTS_DIR/drift-check.sh" "$SKILL_NAME" "$SKILL_PATH" "$LESSONS_DIR" 2>/dev/null) || true

if [[ -n "$DRIFT_OUTPUT" ]]; then
  echo "$DRIFT_OUTPUT"
fi

exit 0
