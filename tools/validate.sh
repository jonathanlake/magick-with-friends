#!/usr/bin/env bash
#
# Pre-PR headless validation gate — runs all three checks from docs/DEV.md:
#   1. Parse-check each changed .gd  (catches syntax errors, incl. brand-new files).
#   2. Import-check the project      (catches broken .tscn/resource refs + errors in
#                                     modified existing scripts).
#   3. Gameplay boot smoke test      (tools/smoke-test.sh — boots a headless host into Main).
#
# Usage:   bash tools/validate.sh
# Exit:    0 = all checks passed (VALIDATE: PASS); 1 = any failure (VALIDATE: FAIL).
# Env:     GODOT=/path/to/godot.exe to override the default Godot 4.6 location.
#
# "Changed .gd" = diff vs the merge-base with origin/main, plus working-tree edits and
# untracked files. Check 1 uses --check-only, which loads no autoloads — so it falsely
# reports "Identifier not found: GameManager/NetworkManager/…" for any script that uses an
# autoload. Only "Parse Error" lines fail the check; everything else is ignored.

set -uo pipefail

GODOT="${GODOT:-/c/Users/Jon/Documents/Game Development/Engines/Godot 4.6/Godot_v4.6-stable_win64.exe}"
PROJ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJ"

if [ ! -x "$GODOT" ]; then
	echo "VALIDATE: FAIL (Godot not found at: $GODOT — set GODOT=...)"
	exit 1
fi

fail=0

# --- Check 1: parse-check changed .gd files --------------------------------------------------
base="$(git merge-base origin/main HEAD 2>/dev/null || true)"
changed="$( {
	[ -n "$base" ] && git diff --name-only --diff-filter=d "$base" -- '*.gd'
	git diff --name-only --diff-filter=d HEAD -- '*.gd'
	git ls-files --others --exclude-standard -- '*.gd'
} | sort -u )"

if [ -z "$changed" ]; then
	echo "CHECK 1 (parse): no changed .gd files — skipped"
else
	while IFS= read -r f; do
		[ -f "$f" ] || continue
		out="$("$GODOT" --headless --path "$PROJ" --check-only --script "res://$f" 2>&1)"
		errors="$(grep 'Parse Error' <<<"$out" || true)"
		if [ -n "$errors" ]; then
			echo "CHECK 1 (parse): FAIL — res://$f"
			echo "$errors"
			fail=1
		else
			echo "CHECK 1 (parse): OK — res://$f"
		fi
	done <<<"$changed"
fi

# --- Check 2: import-check the project --------------------------------------------------------
out="$("$GODOT" --headless --editor --quit --path "$PROJ" 2>&1)"
errors="$(grep -iE 'SCRIPT ERROR|Parse Error|Failed to load' <<<"$out" || true)"
if [ -n "$errors" ]; then
	echo "CHECK 2 (import): FAIL"
	echo "$errors"
	fail=1
else
	echo "CHECK 2 (import): OK"
fi

# --- Check 3: gameplay boot smoke test --------------------------------------------------------
if bash tools/smoke-test.sh; then
	echo "CHECK 3 (smoke): OK"
else
	echo "CHECK 3 (smoke): FAIL"
	fail=1
fi

if [ "$fail" -ne 0 ]; then
	echo "VALIDATE: FAIL"
	exit 1
fi
echo "VALIDATE: PASS"
exit 0
