#!/usr/bin/env bash
# drift-check.sh — Check if a skill has drifted from its last-applied state
# Usage: drift-check.sh <skill-name> <skill-directory-path> [lessons-directory]
# Exit codes:
#   0 = no drift (or no lessons, or drift acknowledged)
#   1 = drift detected, lessons need reapplication
# Output on exit 1: warning message for the user
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_NAME="$1"
SKILL_DIR="$2"
LESSONS_DIR="${3:-$HOME/.claude/compounding-skills-lessons}"

LOCK_FILE="$LESSONS_DIR/$SKILL_NAME.lock.json"

# No lock file = no lessons for this skill
if [[ ! -f "$LOCK_FILE" ]]; then
  exit 0
fi

# Compute current hash
CURRENT_HASH=$("$SCRIPT_DIR/merkle-hash.sh" "$SKILL_DIR")

# Read stored hashes from lock file
STORED_HASH=$(python3 -c "import json,sys; d=json.load(open('$LOCK_FILE')); print(d.get('content_hash',''))")
ACKNOWLEDGED_HASH=$(python3 -c "import json,sys; d=json.load(open('$LOCK_FILE')); print(d.get('drift_acknowledged_hash','') or '')")

# Check: current matches stored → no drift
if [[ "$CURRENT_HASH" == "$STORED_HASH" ]]; then
  exit 0
fi

# Check: current matches acknowledged → user already declined
if [[ -n "$ACKNOWLEDGED_HASH" && "$CURRENT_HASH" == "$ACKNOWLEDGED_HASH" ]]; then
  exit 0
fi

# Drift detected
echo "The \`$SKILL_NAME\` skill has been updated upstream since your lessons were last applied. Run \`/compounding-skills\` in Compound Learning mode to reapply."
exit 1
