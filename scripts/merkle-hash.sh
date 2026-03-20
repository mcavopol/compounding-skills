#!/usr/bin/env bash
# merkle-hash.sh — Compute Merkle hash of a skill directory
# Usage: merkle-hash.sh <skill-directory-path>
# Output: SHA-256 hex string (64 chars)
#
# Computes SHA-256 of each file in the directory (sorted by relative path),
# concatenates "filepath:hash" entries, and hashes the result.
# Raw bytes, includes frontmatter, no normalization.
set -euo pipefail

SKILL_DIR="$1"

if [[ ! -d "$SKILL_DIR" ]]; then
  echo "Error: Directory not found: $SKILL_DIR" >&2
  exit 1
fi

# Find all files, compute per-file hashes, sort by relative path
COMBINED=""
while IFS= read -r file; do
  rel_path="${file#"$SKILL_DIR"/}"
  file_hash=$(shasum -a 256 "$file" | cut -d' ' -f1)
  COMBINED+="${rel_path}:${file_hash}"$'\n'
done < <(find "$SKILL_DIR" -type f -not -path '*/.git/*' -not -name '.DS_Store' | sort)

if [[ -z "$COMBINED" ]]; then
  echo "Error: No files found in $SKILL_DIR" >&2
  exit 1
fi

# Hash the combined string
echo -n "$COMBINED" | shasum -a 256 | cut -d' ' -f1
