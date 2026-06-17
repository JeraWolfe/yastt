# PLAN — YASTT LOD + Retention Ladder

**Author:** C-Bug (with Jera, 2026-05-27)
**Status:** BUILT + VERIFIED 2026-05-27 (Gate 2 given: "just do the code"). Dashboard FULL/WEEK aggregation, WHO-aware legend, and budget-used viz are live; cwatch rollup engine built and dormant (fires only at the user's real weekly reset). Roll-up→verify→scrub proven on a copy (172 pips→18 hourly, delta+cost exact, scrub gated on verify); full multi-week cleanup ladder tested on synthetic data — 7/7 assertions pass, tokens conserved across every tier. **Note: cwatch must be restarted to load the engine (no rush — dormant until the next weekly reset). Dashboard changes are already live on browser refresh.**
**Target tool:** YASTT dashboard (`~/.claude/token_usage.html`), server (`~/.claude/cwatch.js`), data (`~/.claude/token_usage.csv`).

---

## Goal

Add a four-level level-of-detail (LOD) zoom to YASTT and a retention ladder that downsamples old data into coarser summaries and scrubs the raw rows — so `token_usage.csv` stops growing forever while full history is preserved as weekly cost totals.

Display grain coarsens as you zoom out; storage grain coarsens as data ages. They are the same ladder seen from two ends.

---

## Current state (already built this session — DO NOT rebuild)

`token_usage.html`:
- True **time x-axis** (linear ms); session coloring preserved (segment.borderColor by session).
- Palette = **RGB then CMY** (6 colors), cycles. Orange + purple were dropped from sessions and are now marker colors.
- Window zoom buttons **WEEK · DAY · 5H** (in `#timewindow-toggle`); default DAY. `FULL` not yet added.
- **200K / 1M** y-window toggle; y pinned `min:0`, `max` 200000 or 1000000 (tokens tab only).
- **Polling / Realtime** toggle (`#limitmode-toggle`, left of the WHO buttons): Polling re-checks usage on each pip (`fetchAndRefresh` when `changed`); Realtime = 60s timer.
- **Expand/contract arrows** (`#windowsback-toggle`, ◄►/►◄) — show only in Week/5h; `windowsBack` capped 0..1 (one day back in 5h, one week back in Week).
- **Markers** via `buildMarkers()`: compact = **orange** (`#ff8800`, thin, hidden label, fainter at week); 5h-start = **purple** (`#aa44ff`) in 5H view / **red** (`#ff3b3b`) when viewing longer.
- **Phase-locked windows**: `windowBounds()` uses `usageLimits` (live resets) when present, else derivation. `currentWindowEnd()` helper.
- Single render path: `render()` creates the chart once per structure key (`whoFilter|activeTab|datasets.length`), else updates in place → animated slide (800ms easeInOutQuart), no floor-rebuild. `baseOptions()` shared.
- WHO is session-derived (`WHO_ALIAS` maps legacy Bug/Buc/Daw/Bra + ship CLI/DESK/WEB/PLAN → display labels). No magic numbers, no model heuristic.
- `fetchUsage()` reads `cwatch /usage`, sets `usageLimits = { fiveHourResetMs, weeklyResetMs, fiveHourUtil, weeklyUtil, sonnetUtil, opusUtil }`.

`cwatch.js`:
- Static server for `~/.claude/` on :8765, plus **`/usage` route** → reads OAuth token, calls the endpoint, returns JSON. 30s server-side cache, serves stale on error, never logs the token.

Hooks: `token_log_hook.ps1` + `subagent_stop_hook.ps1` write WHO ship labels (cli→CLI, desktop/app→DESK, web→WEB; PLAN is session-assigned).

Data: `token_usage.csv` `who` column backfilled (deadbeef→CLI, 0d563a36→PLAN); `token_usage.csv.bak` saved.

**Outstanding (this plan):** FULL view, the retention/rollup/scrub ladder, and the budget-used utilization viz (data already in `usageLimits`).

---

## The verified data source — OAuth usage endpoint

```
GET https://api.anthropic.com/api/oauth/usage
Headers: Authorization: Bearer <token>,  anthropic-beta: oauth-2025-04-20
Token:   ~/.claude/.credentials.json  ->  claudeAiOauth.accessToken
```
Returns (verified 2026-05-27, this machine): `five_hour {utilization, resets_at}`, `seven_day {…}`, `seven_day_sonnet {…}`, `seven_day_opus` (null if unused), `extra_usage {is_enabled, monthly_limit, used_credits, utilization}`. `resets_at` is ISO 8601 UTC. Treat null fields as N/A. Beta header is a single constant (`OAUTH_BETA` in cwatch.js) — update in one place if it changes. **Never log the token.** Full detail: `devtools/PLAN_rate_limit_tracker_skill.md` (C-Bucks).

---

## Display ladder — four zoom levels

| View | Grain | Y (tokens tab) | Y (cost tab) | Span | Arrows |
|---|---|---|---|---|---|
| **5H**   | raw pips    | context fill        | per-exchange cost | current 5h usage window | +1 day back |
| **DAY**  | raw pips    | context fill        | per-exchange cost | calendar day, 12h morning rollback | none |
| **WEEK** | hourly sums | tokens consumed/hr  | cost/hr           | current billing week | +1 week back |
| **FULL** | weekly sums | tokens consumed/wk  | **cost/wk (primary)** | all billing weeks, back to earliest data | none |

- 5H/Day plot **fill** (a level) from raw pips — unchanged from now.
- Week/Full plot **summed delta** (consumption) — fill doesn't sum across sessions.
- FULL is cost-first ("mostly weekly costs") but respects the active tab (Tokens → weekly tokens, Cost → weekly cost, Cache → weekly avg).
- FULL is billing-week aligned (`seven_day.resets_at`, e.g. Sat 16:00 local), spanning from the earliest retained weekly block to now.
- **FULL has no WHO breakdown** — its source (weekly archive) is WHO-stripped (see Retention). The WHO filter shows ALL-only in FULL; CLI/DESK/PLAN/WEB are inert there by design. 5H/Day/Week keep the full WHO split.

Add a `FULL` button to `#timewindow-toggle`. **Order: `FULL WEEK DAY 5H`** (coarsest → finest, left → right). FULL hides the arrows (`windowsback-toggle`), like Day.

---

## Retention ladder — the cleanup (DESTRUCTIVE)

Every additive field rides the same summation cascade. **delta = tokens used** is the additive quantity; **cost** sums the same way; **cache ratio averages** (it's a ratio). `TokenTotal`/context-fill is a *level* — not summed; it simply doesn't exist in the hourly/weekly tiers (those plot consumption).

```
pip delta  --sum over hour-->  hourly delta  --sum over day-->  daily delta  --sum over week-->  weekly delta
(same cascade for cost; cache averaged)
```

**The condensation principle (Jera, 2026-05-27):** *"For the views where the data is still present, it can be a math step; for the archiving and history (condensing) it should be actually condensed."* While a tier is retained and displayable, WHO is kept so it can be grouped or collapsed on demand (a math step over present data). Once data crosses into the permanent archive it is **truly reduced** — WHO stripped, only the sums survive.

**Tiers & retention:**
| Tier | Granularity | WHO | Retained | Then |
|---|---|---|---|---|
| Pips (raw) | per exchange | per-row | today + yesterday | roll into hourly, **scrub pips** |
| Hourly | per hour | **kept per-WHO** | current week + last week | roll into weekly block, **scrub hourly** |
| Daily | per day | (n/a) | **internal step only** — hourly sums roll straight to weekly; no kept/displayed daily tier, no `yastt_daily.csv` | — |
| **Weekly blocks** | per billing week | **stripped — condensed totals** | **forever** | never scrubbed — this is FULL's source |

**The one hard safety rule — roll up → verify → scrub, in that order:**
1. Compute the coarser sum.
2. Write it and **verify it persisted and equals the sum of the rows it replaces**.
3. **Only then** delete the finer rows.
Never scrub ahead of a verified sum. (Core protocol: don't delete without archiving — here the verified rollup IS the archive.)

**Billing-week alignment:** weekly block boundaries = the `seven_day.resets_at` grid (anchor ± N×7d), so weeks line up with Claude's actual billing weeks, not arbitrary calendar weeks.

---

## Storage

Tiered files in `~/.claude/` (each grain separate, simple to read per view):
- `token_usage.csv` — raw pips (existing; trimmed to ~2 days by the cleanup).
- `yastt_hourly.csv` — hourly sums, **per-WHO** (current + last week). WEEK reads this.
- `yastt_weekly.csv` — weekly blocks, **WHO-stripped condensed totals** (permanent, billing-aligned). FULL reads this.
- No `yastt_daily.csv` — daily is an internal hourly→weekly arithmetic step only.

Headers:
- `yastt_hourly.csv`: `HourStart,DeltaSum,CostSum,CacheAvg,Who` — WHO kept so the WEEK filter still splits CLI/DESK/PLAN/WEB. Session-level collapses (sessions are short-lived; hour is the meaningful grain).
- `yastt_weekly.csv`: `WeekStart,DeltaSum,CostSum,CacheAvg` — no WHO column. Truly condensed: one row per billing week.

Dashboard reads the tier matching the view: 5H/Day → `token_usage.csv`; Week → `yastt_hourly.csv`; FULL → `yastt_weekly.csv`. Parser picks the file by `timeWindow`.

---

## Where the rollup runs

**cwatch.js on a timer.** It's already the always-on server. **Cadence: on startup + every 24h** (Jera's call). Each pass runs the rollup/scrub (roll up → verify → scrub), writing the tier files. Self-maintaining, no dependence on prompts firing. Loose cadence is fine — raw pips are retained today+yesterday, so a once-a-day sweep never scrubs anything still inside its window.

---

## Build order (after sign-off)

1. **Rollup engine** (cwatch or a lib it calls): pips→hourly→daily→weekly, billing-aligned, roll-up→verify→scrub. Write tier files. **Test on a COPY first** (`token_usage.csv.bak` exists; make another). Verify sums equal originals before any scrub runs live.
2. **Dashboard parser**: read the right tier file per `timeWindow`; map summed delta/cost to the chart; Week/Full plot consumption.
3. **FULL button** + `windowBounds()` FULL branch (all weekly blocks → now) + hide arrows in FULL.
4. **Budget-used viz** (utilization): draw `usageLimits.fiveHourUtil / weeklyUtil / sonnetUtil` as a fill/gauge against each window — the "how full am I" indicator. Data already flowing.
5. Verify each view renders from its tier; verify cleanup never loses a token (sum-before/after equality).

---

## Resolved decisions (Jera, 2026-05-27)

1. **Daily tier** → **internal step only.** Hourly sums roll straight into weekly blocks. No `yastt_daily.csv`, no daily zoom level.
2. **Rollup per-WHO?** → **split.** Hourly tier **keeps WHO** (WEEK filter still works — data's present, WHO is a recoverable math grouping). Weekly archive **strips WHO** (truly condensed history — FULL is ALL-only). See the condensation principle in the Retention section.
3. **FULL button position** → **`FULL WEEK DAY 5H`** (coarsest → finest, left → right). FULL prepends; existing buttons shift right one slot.
4. **Cleanup cadence** → **startup + every 24h.** This is the *check* frequency, not the compact frequency — see below.

### Compaction fires at the WEEK boundary, not daily (Jera, 2026-05-27)

*"You don't need to compact 5 hour data until the week end really."* Raw pips stay raw for the entire current billing week. The 5H and Day views read pips directly; **the Week view computes its hourly sums live from those same pips** (math step over present data). Nothing is condensed-and-scrubbed until a billing week rolls off. The 24h cadence is only how often cwatch *checks whether a week boundary has passed* — the actual compact (pips→hourly persist + scrub) runs only at week-end, and the hourly→weekly compact only when an hourly week ages past "last week."

**The compact trigger is the user's weekly reset.** *"It only needs to compact when the user's weekly reset happens."* The boundary is `seven_day.resets_at` from the OAuth endpoint (per-user, real). On each 24h check, cwatch compares now against the last weekly reset it acted on; if a reset has passed, it compacts the week that just closed and records the new boundary. No reset passed → no-op. This makes the engine fully data-driven off the real account reset, not a guessed calendar week.

**Consequence for the display layer:** every view computes the grain it needs from the **finest available source** — recent periods from raw pips, aged-out periods from the tier files — merging at the scrub boundary. With the tier files empty today, all views compute live from pips and the engine is dormant. Gate 2 given 2026-05-27.

---

## Process

Destructive. **Two gates:** C-Bug confirms the plan is clean (Gate 1), Jera says execute (Gate 2). Build on a copy, verify sums, then point live. `token_usage.csv.bak` is the current safety net; make a fresh backup before the first live scrub.

End of plan.
