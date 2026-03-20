#!/usr/bin/env bash
# test-merkle-hash.sh — Tests for merkle-hash.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HASH_SCRIPT="$SCRIPT_DIR/merkle-hash.sh"
PASS=0
FAIL=0

# Helper
assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "PASS: $desc"
    ((PASS++)) || true
  else
    echo "FAIL: $desc"
    echo "  expected: $expected"
    echo "  actual:   $actual"
    ((FAIL++)) || true
  fi
}

assert_ne() {
  local desc="$1" val1="$2" val2="$3"
  if [[ "$val1" != "$val2" ]]; then
    echo "PASS: $desc"
    ((PASS++)) || true
  else
    echo "FAIL: $desc (values should differ but both are: $val1)"
    ((FAIL++)) || true
  fi
}

# Setup temp directory
TMPDIR_BASE=$(mktemp -d)
trap "rm -rf $TMPDIR_BASE" EXIT

# Test 1: Single file produces a hash
SKILL_DIR="$TMPDIR_BASE/test1"
mkdir -p "$SKILL_DIR"
echo "# Test skill" > "$SKILL_DIR/SKILL.md"
HASH1=$("$HASH_SCRIPT" "$SKILL_DIR")
assert_eq "Single file produces non-empty hash" "64" "${#HASH1}"

# Test 2: Same content produces same hash (deterministic)
SKILL_DIR2="$TMPDIR_BASE/test2"
mkdir -p "$SKILL_DIR2"
echo "# Test skill" > "$SKILL_DIR2/SKILL.md"
HASH2=$("$HASH_SCRIPT" "$SKILL_DIR2")
assert_eq "Same content produces same hash" "$HASH1" "$HASH2"

# Test 3: Different content produces different hash
echo "# Different skill" > "$SKILL_DIR2/SKILL.md"
HASH3=$("$HASH_SCRIPT" "$SKILL_DIR2")
assert_ne "Different content produces different hash" "$HASH1" "$HASH3"

# Test 4: Adding a file changes the hash
mkdir -p "$SKILL_DIR/scripts"
echo "helper code" > "$SKILL_DIR/scripts/helper.sh"
HASH4=$("$HASH_SCRIPT" "$SKILL_DIR")
assert_ne "Adding a file changes the hash" "$HASH1" "$HASH4"

# Test 5: File order doesn't matter (sorted paths)
SKILL_DIR3="$TMPDIR_BASE/test3"
mkdir -p "$SKILL_DIR3/scripts"
echo "helper code" > "$SKILL_DIR3/scripts/helper.sh"
echo "# Test skill" > "$SKILL_DIR3/SKILL.md"
HASH5=$("$HASH_SCRIPT" "$SKILL_DIR3")
assert_eq "File creation order doesn't affect hash" "$HASH4" "$HASH5"

# Test 6: Non-existent directory returns error
if "$HASH_SCRIPT" "$TMPDIR_BASE/nonexistent" 2>/dev/null; then
  echo "FAIL: Non-existent directory should error"
  ((FAIL++)) || true
else
  echo "PASS: Non-existent directory returns error"
  ((PASS++)) || true
fi

# Summary
echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
