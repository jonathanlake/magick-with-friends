# tools/

Dev tooling for the project.

## `validate.sh` — the full pre-PR headless gate

Runs all **three** checks from `docs/DEV.md` → Headless Validation in one command: parse-check
each changed `.gd`, import-check the project, then the gameplay boot smoke test below.

**Run** (Git Bash, from the project root — also exposed as the `/validate` skill):

```
bash tools/validate.sh
```

- `VALIDATE: PASS` (exit 0) — all three checks passed; OK to open the PR.
- `VALIDATE: FAIL` (exit 1) — at least one check failed; the failing check prints its errors.
- Override Godot's location: `GODOT=/c/path/to/Godot.exe bash tools/validate.sh`

Check 1 fails **only** on `Parse Error` lines — `--check-only` loads no autoloads, so its
`Identifier not found: GameManager/…` complaints are false positives the script filters out.

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
in `docs/DEV.md`. Host-driven only: it does **not** exercise input (casting/movement); that
stays with the two-window playtest.

**Want proof it's real, not just printing "PASS"?** Temporarily break the boot — e.g. add a
bad line to `main.gd`'s `_ready()` — and run it; it flips to `SMOKE: FAIL`. The `SMOKE_OK`
line only prints when the host player node genuinely exists in the live scene tree, and it
prints that node's *real* path plus which components are wired — state that can only be true
if the game actually booted.
