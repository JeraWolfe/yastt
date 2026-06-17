# YASTT — Pickup Notes

**Last updated:** 2026-06-17
**Updated by:** C-Bug (claude-gml-plugin instance) during cross-project housecleaning.

This file exists so the next Claude instance to resume work on YASTT (via `C:\Users\jeraw\yasttproject.bat`) lands warm instead of cold.

---

## Quick facts

- **Project:** YASTT (token usage dashboard, packaged for general distribution).
- **Repo:** `github.com/JeraWolfe/yastt` (PUBLIC, Apache-2.0, 0.1.0-alpha). Last GitHub push: 2026-05-27.
- **Local path:** `C:\Users\jeraw\source\repos\yastt\`.
- **Launcher:** `C:\Users\jeraw\yasttproject.bat` (cd's here + opens cwatch dashboard + `claude --dangerously-skip-permissions --resume`).
- **Relationship to other artifacts:**
  - SEPARATE from Jera's live `~/.claude` dashboard. That dashboard is driven by `%USERPROFILE%\.claude\cwatch.js` (the installed copy) — not the YASTT source.
  - The `/cwatch` skill at `.claude/commands/cwatch.md` (in other project dirs) is the dashboard-opening helper, also distinct from YASTT package code.

## What landed here on 2026-06-17 (migrated from `claude-gml-plugin`)

A previous YASTT/CWATCH development thread left construction artifacts inside the `claude-gml-plugin` GameMaker project. Those have been moved into this repo's `dev_notes/` directory so the projects are cleanly separated.

### `dev_notes/PLAN_yastt_lod_retention.md`
Active design plan for YASTT's LOD (level-of-detail) retention behavior. Originally lived at `claude-gml-plugin/devtools/PARKED/PLANS/PLAN_yastt_lod_retention.md`. Preserved verbatim. Open this first if the resumed session needs to continue YASTT design work — it's the most load-bearing of the migrated files.

### `dev_notes/screenshots/`
Visual context from earlier YASTT/CWATCH dev work, all dated 2026-05-27 (4 yastt) plus a few undated cwatch state captures.

| File | What it shows (best inference from filename) |
|---|---|
| `cwatch_check.png` | cwatch with a "check" state visible |
| `cwatch_cost.png` | cwatch cost-display view |
| `cwatch_fixed.png` | cwatch after some fix landed |
| `cwatch_current_state_20260527_095435.png` | cwatch state snapshot 2026-05-27 09:54:35 |
| `yastt_blue_end_20260527_110434.png` | YASTT UI "blue end" state |
| `yastt_expand_crunch_20260527_152709.png` | YASTT expand-crunch interaction |
| `yastt_slide_layout_20260527_154926.png` | YASTT slide layout view |
| `yastt_copyright_view_20260527_175539.png` | YASTT copyright view |

(File contents are PNGs — open in an image viewer for actual context.)

## Known open thread

Jera flagged: **CWATCH recursively calls itself as a skill/tool when working on itself.** Working on YASTT means the cwatch dashboard for monitoring the session is using the same code that's being edited (the installed `%USERPROFILE%\.claude\cwatch.js`, presumably the deployed/installed version of YASTT). This is on his "list of things to fix." Watch for it during this session if any edits to the cwatch server code produce confusing live-dashboard behavior.

## What is NOT here (and should not be)

- The `/cwatch` skill file lives globally and in other project-local `.claude/commands/` directories. NOT migrated to this repo — it's a Claude Code helper, separate from YASTT package source.
- The deployed `%USERPROFILE%\.claude\cwatch.js` is the installed copy, not source. Source for it (if a deployable cwatch script exists separately from YASTT itself) is unclear — investigate if needed.

## Repo structure (top level)

- `.claude-plugin/` — Claude Code plugin metadata
- `commands/` — slash commands shipped with YASTT
- `docs/` — public-facing documentation
- `hooks/` — Claude Code hooks
- `server/` — server code
- `dev_notes/` — **THIS DIR. Internal dev artifacts. Not necessarily shipped.**
- `install.ps1` / `install.sh` — installers
- `README.md`, `LICENSE`, `NOTICE`, `CHANGELOG.md`, `FUTURE_IDEAS.md`
- `bug_two_cli_sessions_connected_20260608_145126.png` — bug evidence already in repo (separate from the 2026-06-17 migration)

## .gitignore consideration

The migrated files have not been added to `.gitignore`. If they should not be committed to GitHub (since they are internal dev artifacts), add `dev_notes/` to `.gitignore` before the next push. If they should be tracked as project documentation, `git add dev_notes/` and commit. Default: TBD — Jera's call on first session.
