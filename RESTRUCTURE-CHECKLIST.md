# Restructure Checklist — do these moves IN THE GODOT EDITOR (FileSystem dock)

**Why the editor:** dragging files in the FileSystem dock makes Godot rewrite every scene's
dependency paths automatically (25 `path="res://…"` refs across 13 scenes, several without
uids). Do **not** move these in Explorer/git and do **not** hand-edit any paths — drag, drop,
done. Claude fixes everything the editor doesn't (project.godot autoloads, script preloads,
the smoke test) afterwards.

**Order tip:** create the folders first (right-click → New Folder), then drag. If the editor
asks to save scenes during a move, say yes.

## 1. Create folders

- [ ] `framework/` with subfolders: `autoloads`, `components`, `debug`, `resources`, `ui`
- [ ] `games/magick/` with subfolders: `spells`, `reactions`, `director`, `player`,
      `enemies`, `projectiles`, `hud`, `levels`

## 2. Drag into `framework/`

- [ ] `autoloads/game_events.gd`      → `framework/autoloads/`
- [ ] `autoloads/game_manager.gd`     → `framework/autoloads/`
- [ ] `autoloads/network_manager.gd`  → `framework/autoloads/`
      (NOT `spell_catalog.gd` — that one goes to games/magick below)
- [ ] everything in `components/` (all .gd + .tscn: health, hit_flash, stamina,
      player_input_synchronizer, locomotion_animator, spine_pitch_modifier,
      remote_visual_smoother) → `framework/components/`
- [ ] `debug/debug.gd`                → `framework/debug/`
- [ ] `resources/game_config.gd`      → `framework/resources/`
- [ ] `ui/main_menu/` (whole folder)  → `framework/ui/main_menu/`
- [ ] `ui/console/` (whole folder)    → `framework/ui/console/`

## 3. Drag into `games/magick/`

- [ ] `autoloads/spell_catalog.gd`    → `games/magick/` (top level of magick)
- [ ] contents of `systems/spells/`   → `games/magick/spells/`
- [ ] contents of `systems/reactions/`→ `games/magick/reactions/`
- [ ] contents of `systems/director/` → `games/magick/director/`
- [ ] contents of `entities/player/`  → `games/magick/player/`
- [ ] contents of `entities/enemies/` → `games/magick/enemies/`
- [ ] contents of `entities/projectiles/` → `games/magick/projectiles/`
- [ ] `ui/hud/` (whole folder)        → `games/magick/hud/`
- [ ] `test_level.tscn`               → `games/magick/levels/`

## 4. Clean up + verify (still in the editor)

- [ ] Delete the now-empty old folders: `autoloads/`, `components/`, `debug/`, `resources/`,
      `systems/`, `entities/`, `ui/` (only if empty — `ui/` should be empty after main_menu,
      console, and hud moved)
- [ ] Scene → **Save All Scenes**
- [ ] **Run the game once (F5)** — main menu appearing without a wall of errors = good.
      (Hosting may complain about autoload paths — that's expected, Claude fixes
      project.godot next. The menu loading is the signal that scene refs survived.)
- [ ] Quit the editor

## 5. Hand back to Claude

Say "moves done" (mention anything that looked off). Claude then fixes `project.godot`,
the 4 script preloads, `tools/smoke-test.sh`, runs the full validation gate, syncs all docs,
deletes this checklist, and opens the PR.
