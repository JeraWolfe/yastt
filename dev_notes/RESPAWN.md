# RESPAWN.md — read FIRST after a context compact

## Immediate state (2026-06-30)
- Working on **YASTT** at `C:\Users\jeraw\source\repos\yastt`. Then read `dev_notes/GHOST.md` + `dev_notes/PICKUP.md`.
- Live server: `node ~/.claude/yastt/cwatch.js` on `localhost:8765` with a **continuous 60s `/usage`
  sampler** appending `~/.claude/yastt/yastt_util_samples.csv`. Dashboard: `~/.claude/yastt/token_usage.html`.
- Check `git status -sb` for unpushed work.

## What's in flight
**Designer/cmonkey cloud-usage estimation.** The sampler is banking `(5h %, local-token)` pairs and has
already captured Designer bumps (5h stepping up ~1% while local tokens stay flat). Not yet visualized.

## Immediate next move on wake
Build **B — the Designer estimator**:
1. From `yastt_util_samples.csv`, calibrate **tokens-per-1% off the 5-HOUR bucket** (NOT weekly) using
   clean (non-Designer) intervals — exclude known/suspected Designer bumps.
2. Convert Designer bumps (5h↑ while localΔ=0) to estimated tokens/cost.
3. Render Designer as a **special magenta agent** in the Agents tab (estimated, not a real session).
4. Add the two views: **incremental** (quarantine — each bump from 0) and **cumulative** (running total,
   weekly-reset subtotals), summed in the page via a **toggle button**; estimates stay quarantined in
   their own file.

## Deploy / verify recipe
Edit repo `server/*` → copy to `~/.claude/yastt/`. HTML: browser refresh. cwatch.js: stop the PID on
8765, then `Start-Process node "~/.claude/yastt/cwatch.js"`. Verify with Playwright at localhost:8765.
**Back up live files before destructive edits** (pattern: `*.bak_*`).
