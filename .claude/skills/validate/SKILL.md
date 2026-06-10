---
name: validate
description: Run the pre-PR headless validation gate (parse-check changed GDScript, import-check the project, gameplay boot smoke test). Use before opening any code PR, or when asked to validate / headless-check / smoke-test the project.
---

# Validate — the pre-PR headless gate

Run all three checks with one command, via the **Bash** tool (the script needs Git Bash):

```bash
bash tools/validate.sh
```

- `VALIDATE: PASS` (exit 0) — gate passed; OK to open the PR.
- `VALIDATE: FAIL` (exit 1) — **do not open the PR.** Fix the failure and re-run.
- Non-default Godot location: prefix with `GODOT=/c/path/to/Godot.exe`.

## Reading failures

- **CHECK 1 (parse)** fails only on `Parse Error` lines in changed `.gd` files. The script
  already filters out the `--check-only` false positives (`Identifier not found:
  GameManager / NetworkManager / …` — autoloads aren't loaded in that mode); if you run the
  raw command yourself, ignore those lines.
- **CHECK 2 (import)** fails on `SCRIPT ERROR` / `Parse Error` / `Failed to load` — usually a
  broken `.tscn`/resource reference, or an error in a modified *existing* script.
- **CHECK 3 (smoke)** boots a headless host into gameplay (`tools/smoke-test.sh`). Failures
  are runtime/boot errors — read the `--- smoke output ---` block it prints. It temporarily
  enables the DEBUG autoload in `project.godot` and restores it on exit.

## Scope

The gate catches "won't parse / won't load / won't boot" — it does **not** exercise input
(casting/movement); that stays with the two-window playtest. Full rationale and the per-check
details: `docs/DEV.md` → Headless Validation.
