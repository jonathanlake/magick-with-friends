#!/usr/bin/env bash
#
# Headless gameplay smoke test (Tier 1).
#
# Boots a headless HOST into the actual game (Main, host player spawned), verifies it
# reached gameplay, and fails on any logged runtime error. This is the third check of the
# pre-PR "Headless Validation" gate (see docs/DEV.md; tools/validate.sh runs all three) —
# it confirms the project not only *loads* (parse + import checks) but actually *runs*.
# Host-driven only: it does not
# exercise input (casting/movement); that's what the two-window playtest is for.
#
# Usage:   bash tools/smoke-test.sh
# Exit:    0 = booted into gameplay with no errors; 1 = failure.
# Env:     GODOT=/path/to/godot.exe to override the default Godot 4.6 location.

set -uo pipefail

GODOT="${GODOT:-/c/Users/Jon/Documents/Game Development/Engines/Godot 4.6/Godot_v4.6-stable_win64.exe}"
PROJ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJ"

if [ ! -x "$GODOT" ]; then
	echo "SMOKE: FAIL (Godot not found at: $GODOT — set GODOT=...)"
	exit 1
fi

# The smoke driver lives in the DEBUG autoload, which is disabled by default. Enable it for
# this run only, and restore the exact original project.godot on exit no matter what.
BAK="$(mktemp)"
cp project.godot "$BAK"
trap 'cp "$BAK" project.godot; rm -f "$BAK"' EXIT
sed -i 's|DEBUG="res://framework/debug/debug.gd"|DEBUG="*res://framework/debug/debug.gd"|' project.godot

LOG="$(mktemp)"
# --quit-after is a frame backstop; the smoke driver normally quits itself within ~31 frames.
"$GODOT" --headless --quit-after 300 --path "$PROJ" -- smoke > "$LOG" 2>&1
godot_exit=$?

echo "--- smoke output ---"
cat "$LOG"
echo "--------------------"

# Real errors. (Ignore "N resources still in use at exit", which prints on clean headless quits.)
errors="$(grep -iE 'SCRIPT ERROR|Parse Error|Failed to load|Failed to instantiate' "$LOG" || true)"
ok="$(grep -c 'SMOKE_OK' "$LOG" || true)"
rm -f "$LOG"

if [ -n "$errors" ]; then
	echo "SMOKE: FAIL (runtime errors logged)"
	exit 1
fi
if [ "${ok:-0}" -lt 1 ]; then
	echo "SMOKE: FAIL (host did not boot into gameplay — no SMOKE_OK; godot exit $godot_exit)"
	exit 1
fi
echo "SMOKE: PASS"
exit 0
