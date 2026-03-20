#!/usr/bin/env bash
# test-drift-check.sh — Tests for drift-check.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DRIFT_SCRIPT="$SCRIPT_DIR/drift-check.sh"
HASH_SCRIPT="$SCRIPT_DIR/merkle-hash.sh"
PASS=0
FAIL=0

assert_exit() {
  local desc="$1" expected_exit="$2"
  shift 2
  set +e
  OUTPUT=$("$@" 2>&1)
  ACTUAL_EXIT=$?
  set -e
  if [[ "$ACTUAL_EXIT" -eq "$expected_exit" ]]; then
    echo "PASS: $desc"
    ((PASS++)) || true
  else
    echo "FAIL: $desc (expected exit $expected_exit, got $ACTUAL_EXIT)"
    echo "  output: $OUTPUT"
    ((FAIL++)) || true
  fi
}

# Setup
TMPDIR_BASE=$(mktemp -d)
trap "rm -rf $TMPDIR_BASE" EXIT
LESSONS_DIR="$TMPDIR_BASE/lessons"
SKILL_DIR="$TMPDIR_BASE/skill"
mkdir -p "$LESSONS_DIR" "$SKILL_DIR"
echo "# Test skill" > "$SKILL_DIR/SKILL.md"

# Test 1: No lock file → exit 0 (no lessons, no drift)
assert_exit "No lock file exits 0" 0 "$DRIFT_SCRIPT" "test-skill" "$SKILL_DIR" "$LESSONS_DIR"

# Test 2: Lock file with matching hash → exit 0 (no drift)
CURRENT_HASH=$("$HASH_SCRIPT" "$SKILL_DIR")
cat > "$LESSONS_DIR/test-skill.lock.json" << EOF
{
  "format_version": 1,
  "skill_path": "$SKILL_DIR/SKILL.md",
  "content_hash": "$CURRENT_HASH",
  "hash_captured_at": "2026-03-20T14:00:00Z",
  "lessons_applied": ["L001"],
  "drift_acknowledged_hash": null
}
EOF
assert_exit "Matching hash exits 0" 0 "$DRIFT_SCRIPT" "test-skill" "$SKILL_DIR" "$LESSONS_DIR"

# Test 3: Lock file with different hash → exit 1 (drift detected)
echo "# Modified skill" > "$SKILL_DIR/SKILL.md"
assert_exit "Different hash exits 1" 1 "$DRIFT_SCRIPT" "test-skill" "$SKILL_DIR" "$LESSONS_DIR"

# Test 4: Drift acknowledged hash matches current → exit 0 (user already declined)
NEW_HASH=$("$HASH_SCRIPT" "$SKILL_DIR")
cat > "$LESSONS_DIR/test-skill.lock.json" << EOF
{
  "format_version": 1,
  "skill_path": "$SKILL_DIR/SKILL.md",
  "content_hash": "old-hash",
  "hash_captured_at": "2026-03-20T14:00:00Z",
  "lessons_applied": ["L001"],
  "drift_acknowledged_hash": "$NEW_HASH"
}
EOF
assert_exit "Acknowledged drift exits 0" 0 "$DRIFT_SCRIPT" "test-skill" "$SKILL_DIR" "$LESSONS_DIR"

# Summary
echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
