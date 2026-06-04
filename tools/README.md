# tools/

Dev tooling for the project.

## `smoke-test.sh` — headless gameplay smoke test

Boots a headless **host** into the game, verifies the host player actually spawned, and
fails on any runtime error. The fast "did I break the boot?" check — no editor, ~3s.

**Run** (Git Bash, from the project root):

```
bash tools/smoke-test.sh
```

- `SMOKE: PASS` (exit 0) — booted into gameplay, host player spawned, no errors.
- `SMOKE: FAIL` (exit 1) — a runtime error was logged, or the host player didn't spawn.
- Override Godot's location: `GODOT=/c/path/to/Godot.exe bash tools/smoke-test.sh`

It only edits `project.godot` (to enable the `DEBUG` autoload) for the duration of the run
and restores it on exit. This is **check 3** of the pre-PR gate — see "Headless Validation"
in `CLAUDE.md`. Host-driven only: it does **not** exercise input (casting/movement); that
stays with the two-window playtest.

**Want proof it's real, not just printing "PASS"?** Temporarily break the boot — e.g. add a
bad line to `main.gd`'s `_ready()` — and run it; it flips to `SMOKE: FAIL`. The `SMOKE_OK`
line only prints when the host player node genuinely exists in the live scene tree, and it
prints that node's *real* path plus which components are wired — state that can only be true
if the game actually booted.
