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

# Validate skill name — alphanumeric, hyphens, underscores only
if [[ ! "$SKILL_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
  echo "Error: invalid skill name: $SKILL_NAME" >&2
  exit 1
fi

LOCK_FILE="$LESSONS_DIR/$SKILL_NAME.lock.json"

# No lock file = no lessons for this skill
if [[ ! -f "$LOCK_FILE" ]]; then
  exit 0
fi

# Compute current hash
CURRENT_HASH=$("$SCRIPT_DIR/merkle-hash.sh" "$SKILL_DIR")

# Read stored hashes from lock file (pass path via env to avoid shell injection into python)
STORED_HASH=$(LOCK_FILE="$LOCK_FILE" python3 -c "
import json, os
d = json.load(open(os.environ['LOCK_FILE']))
print(d.get('content_hash', ''))
")
ACKNOWLEDGED_HASH=$(LOCK_FILE="$LOCK_FILE" python3 -c "
import json, os
d = json.load(open(os.environ['LOCK_FILE']))
print(d.get('drift_acknowledged_hash', '') or '')
")

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
