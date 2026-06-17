# ULTRAPLAN PROMPT — YASTT Dashboard Overhaul (8 items)

**Author:** C-Bug, 2026-06-17. Drafted for Jera's review (process Step 2). NOT yet sent to the planner.
**Status:** DRAFT — pending Jera review of the CONFIRM-BEFORE-SENDING flags, then revision, then planner.

---

## ⚠️ CONFIRM-BEFORE-SENDING (Jera decides; these are C-Bug's interpretations, not facts)

These five calls are baked into the prompt below. Confirm or correct each before this goes to the planner.

- **(A) Persistent "every dot" log vs the retention ladder.** Item 5 says "keep a persistent log of every dot, full history." The existing LOD/retention ladder *deliberately scrubs raw pips* from `token_usage.csv` after a billing week to stop unbounded growth (`cwatch.js` `compactPipsWeek`). To honor BOTH, the prompt proposes a **new append-only master log `yastt_log.csv` that is NEVER scrubbed** (feeds the Log tab + all-time cost), while `token_usage.csv` + the retention ladder stay exactly as-is for chart performance. **Alternative:** stop scrubbing pips entirely and make `token_usage.csv` the permanent log (defangs the retention ladder you designed). Default = new master log. **Confirm.**
- **(B) Agents chart time alignment.** "Same time dots as the one up top" → the prompt aligns the Agents x-axis to the **top chart's current [min,max] window AND overlays the same 5h/compact markers**, so bars line up vertically under the token chart. Confirm that's what you want (vs. agents keeping their own independent time axis with only the markers copied).
- **(C) Compact guard location.** The prompt fixes the guard in BOTH places: the **hook** (go-forward correctness) AND the **dashboard** (re-derive compacts from session+model continuity so your *existing* 49 phantom markers clear immediately without rewriting history). Confirm you want the dashboard re-derivation too (it makes WEEK/DAY clean right now).
- **(D) All-time cost source.** All-time total = sum of costs in the new master log (every exchange) + the weekly archive if/when it holds older data, across ALL models, ignoring every filter and view. Confirm.
- **(E) Build as ONE plan or split.** 8 items is a large plan. C-Bug recommends the planner deliver it as **one plan with the build order below**, executed/verified in phases. Confirm one-plan vs. split into 2-3 smaller prompts.

---

## CONTEXT FOR THE PLANNER (you start cold from main — read this first)

YASTT is a local Claude Code token dashboard. A Node server `server/cwatch.js` serves a single-file
Chart.js dashboard `server/token_usage.html` on `localhost:8765`. Two hooks log usage to CSVs in
`~/.claude/yastt/`:
- `hooks/token_log.ps1` / `hooks/token_log.sh` (UserPromptSubmit) → one row per exchange ("pip") to `token_usage.csv`.
- `hooks/subagent_stop.ps1` / `hooks/subagent_stop.sh` (SubagentStop) → one row per sub-agent to `agent_usage.csv`.

**CSV schemas (column order is load-bearing — the dashboard parser indexes by position):**
- `token_usage.csv`: `TokenDelta,TokenTotal,Percentage,Date,Time,Flag,Session,Who,Model,Cost,CacheRatio` (indices 0..10).
- `agent_usage.csv`: `AgentId,ContextFill,ToolUses,Cost,CacheRatio,Model,Date,Time,ParentSession,ParentWho` (indices 0..9).

**LOD/retention architecture (DO NOT BREAK):** display grain coarsens as you zoom out (5h/day = raw
pips → week = hourly sums → full = weekly sums); storage grain coarsens as data ages (pips scrubbed
after a billing week into `yastt_hourly.csv`, then `yastt_weekly.csv`). The rollup runs in `cwatch.js`
on a 24h timer, fires only at the user's real weekly reset, and obeys ROLL-UP → VERIFY → SCRUB. It is
currently dormant (no week has aged off). Tier files are empty today, so every view aggregates live
from raw pips. **Preserve this entire mechanism.**

**Style / naming constraints (hard):**
- Dashboard JS: match the existing **camelCase** identifiers and idioms (`makeChart`, `whoFilter`,
  `sessionColor`, `rowColor`). Do not introduce snake_case into the JS — consistency with the file wins.
- Hooks (.ps1/.sh): match the existing **snake_case** style (`$context_fill`, `$last_model`).
- No single-letter names except loop counters. Spell concepts out.
- Every change to a hook must be applied to **both** the `.ps1` and the `.sh` variant (cross-platform parity).
- The OAuth token must never be logged, copied, or transmitted (existing invariant in `cwatch.js`).

---

## THE 8 ITEMS

### 1. Isolate individual sessions (break the line at session boundaries)
**Current:** In `makeAllModeChart` (`token_usage.html:700`) and `makeSingleModeChart` (`:737`), all of a
WHO's pips go into one `pts` array drawn as a single continuous line; `segment.borderColor` recolors
per-segment via `rowColor(p._r)` but the stroke still connects across sessions. Visible artifact: in 5h,
one session's last point connects straight down to the next session's first point (a false vertical).
**Change:** Break the line at every session boundary so each session is its own isolated trace (no
connecting stroke between different `session` values). Applies in BOTH color modes and every view that
plots raw pips. Implementation is the planner's call (per-session datasets, or a transparent segment
when `pts[p0].session !== pts[p1].session`), but points must stay; only the cross-session connector goes.
**Verify:** In 5h/day with ≥2 interleaved sessions, no stroke connects points of different sessions.

### 2. FULL view shows real full history, earliest record → now
**Current:** FULL reads `weeklyTier` (empty) and live-aggregates `allRows` by `weekStart`
(`displayRows` `:434`). With < 1 week of data it yields a single weekly bucket → one dot at the far left
(`yastt_full.png`), so FULL "shows nothing." `windowBounds` full branch (`:466`) already sets min =
earliest record, which is correct.
**Change:** FULL must render the **complete history meaningfully**, merging the permanent weekly archive
(`yastt_weekly.csv`) with live-aggregated current/recent weeks, starting at the genuine earliest record
and running to now — and must render visibly even when only sub-week / single-week data exists (don't
collapse to an invisible single point). Coordinate with item (A): the all-history source must survive
pip scrubbing. Keep FULL cost-first per the existing design but respect the active tab.
**Verify:** FULL plots from the first recorded activity forward; with only a few days of data it still
shows a legible series, not one dot.

### 3. Agents chart: scatter dots → horizontal bars (Gantt-style)
**Current:** `renderAgentChart` (`:955`) is a `type:'scatter'`; x = stop time, y = totalTokens, colored
by `parentWho` (`WHO_COLORS`). `agent_usage.csv` has `ContextFill` but **no duration** — only one stop
timestamp. `ToolUses` is a known-broken `0` (out of scope here unless trivially adjacent).
**Change:**
- **Hook (both .ps1 + .sh `subagent_stop`):** add a `Duration` column = (last transcript entry timestamp −
  first transcript entry timestamp) in ms, parsed from the agent's own transcript JSONL `timestamp`
  fields. Append the column to the header and the row write. Update the dashboard parser
  `parseAgentCSV` (`:929`) to read it.
- **Dashboard:** redraw each agent as a **horizontal bar**: x-extent = `[start, start + Duration]`
  (length = time used), **thickness ∝ ContextFill** (token count / context %), color + marker-shape by
  `parentWho` mirroring the top chart (see item 7: CLI dot/●-tone, DESK triangle/▲-tone). Align the
  agents x-axis to the **top chart's [min,max]** and overlay the **same 5h/compact markers**
  (`buildMarkers`) — see flag (B). Chart.js approach is the planner's call (floating bars / custom
  draw); thickness-encodes-tokens on a time axis is non-standard, so design it explicitly.
**Verify:** Each agent is a horizontal bar whose length tracks its duration and thickness tracks its
context fill, time-aligned beneath the token chart with matching markers.

### 4. Merge the window-expand arrows into one toggle
**Current:** `#windowsback-toggle` (`:159-162`) is two buttons — `expandWindow(1)` (◄►) and
`expandWindow(-1)` (►◄); `windowsBack` is capped 0..1 (`:575`).
**Change:** Replace the two buttons with a **single toggle button** that flips `windowsBack` 0↔1 (and
reflects state visually). Keep visibility rules (week/5h only) intact.
**Verify:** One button toggles the previous-window inclusion; behavior identical to the old pair.

### 5. Persistent inverted log + a Log tab
**Current:** Hooks append to `token_usage.csv`; the dashboard parses the whole file each poll. Tabs
(`:115-132`) are Tokens/Cost/Cache and switch the chart metric.
**Change:**
- **Storage:** keep **append** (O(1) writes; no prepend). Per flag (A), the hook also appends every
  exchange to a NEVER-scrubbed master log `yastt_log.csv` (same schema as `token_usage.csv`) so full
  per-dot history persists beyond the retention window.
- **Read newest-first:** the Log view reads the master log and presents **most-recent-first** (reverse
  on read; storage stays chronological/append).
- **Log tab:** add a **Log tab** to the tab bar — **not default-open**, tucked out of the way (e.g. last
  tab) — that replaces the chart area with a scrollable newest-first table of every exchange
  (time, session, who, model, delta, total, cost, cache, compact flag). Switching back to
  Tokens/Cost/Cache restores the chart.
**Verify:** Log tab is non-default, lists every exchange newest-first; chart tabs unaffected.

### 6. Compact detection guard — same SESSION **and** MODEL
**Current (the bug):** `token_log.ps1:113-122` reads `$prev_total` from the **last CSV row regardless of
session/model**; `$delta = $context_fill - $prev_total`; `$delta < 0` → flag `"C"` (`:127-130`). With
multiple interleaved sessions, a different session's prior total makes delta negative → phantom compacts
(observed: 49). The dashboard trusts this flag for markers (`buildMarkers:531`) and the Compacts stat
(`updateStats:327`).
**Change:**
- **Hook (both .ps1 + .sh `token_log`):** compute `prev_total` from the most recent prior row of the
  **same Session AND same Model**, not the global last row. Flag `"C"` only when that same-thread delta
  is negative. When no same-thread prior row exists (new session/model), treat as a fresh thread
  (`delta = context_fill`, no flag). This makes delta mean within-thread context growth.
- **Dashboard (flag C):** re-derive compact markers from **session+model continuity between adjacent
  same-session points** rather than blindly trusting the stored flag, so the existing phantom markers
  clear without rewriting history. (Keep reading the flag as a fallback for rows where re-derivation
  isn't possible.)
**Verify:** Switching between sessions/models produces NO compact marker; a genuine in-session context
drop (real /compact) still does. The 49 count falls to the true number.

### 7. Session ↔ Model color toggle (with model-shade scheme) + client marker SHAPE
**Current:** A `#colormode-toggle` already exists (`:163-166`) with "Session" / "5h Block" and
`setColorMode` (`:883`), but only shows when `whoFilter !== 'all'`. Color is per-session
(`sessionColor`) or per-5h-block. Model is already logged (index 8) and shown in the all-mode tooltip
(`:658`). Marker shape is the Chart.js default (circle) for everyone.
**Change:**
- Replace/extend the color toggle to **Session ↔ Model** (the "5h Block" mode may be dropped or kept at
  planner's discretion; Session + Model are the required modes), and make the toggle available in raw
  views **regardless of who filter** (Jera views 4 sessions in ALL mode).
- **Session mode (default):** per-session color, as today, plus the isolation from item 1.
- **Model mode:** assign each model family a **base hue, auto-assigned in first-seen order** from the
  palette; render the sessions of a given model as **shades of that base hue**, varying **lightness +
  saturation together** (spread for separation). N = number of sessions of that model **in the current
  visible window** (recompute on pan/zoom). Today = 4 sessions / 1 model → 4 shades of one hue.
- **Marker SHAPE encodes the client (WHO), not color:** **CLI = circle (●), Desktop = triangle (▲)**
  (Chart.js `pointStyle` per point). Applies to the top chart and the agent bars (item 3).
- **Tooltip:** show the model name in both modes (already present in all-mode; ensure single-mode too).
**Verify:** Toggle flips Session↔Model in ALL mode; Model mode shows one hue per model with
per-session shades; CLI points are circles, DESK points triangles; model appears in the tooltip.

### 8. All-time running total cost, inside the 7D expansion panel
**Current:** The Cost stat (`updateStats:318-324`) is scoped to the current window+filters, so it
changes per view ($150 / $270 / $15.89 across Day/Full/5h). The 7D expansion = `limit-row` /
`renderModelRow` (`:819`), revealed by the 7D chip (`toggleLimits:854`).
**Change:** Add an **all-time total cost** tile **inside the expanded 7D panel** (`renderModelRow`):
account-wide, across **all models**, independent of the current window and every filter. Source per
flag (D): the master log (every exchange) + the weekly archive's cost sums when present.
**Verify:** The all-time cost shows in the expanded 7D panel, identical regardless of which view/filter
is active, and equals the true sum of all recorded exchange costs.

---

## RECOMMENDED BUILD ORDER (planner may refine)

1. **Hooks (data layer):** item 6 (compact guard) + item 3 (Duration column) + item 5 (write
   `yastt_log.csv`). Both .ps1 and .sh. Schema/header changes first so the dashboard has data to read.
2. **cwatch.js:** ensure `yastt_log.csv` is served (it's a `.csv` from DATA_DIR — already covered by the
   static route) and untouched by the rollup; confirm retention ladder still targets only
   `token_usage.csv`.
3. **Dashboard data plumbing:** parse `yastt_log.csv`; all-time cost (item 8); dashboard-side compact
   re-derivation (item 6).
4. **Top chart:** session isolation (item 1); Session↔Model toggle + shades + marker shapes (item 7);
   FULL full-history render (item 2).
5. **Agents chart:** rebuild as time-aligned horizontal bars (item 3).
6. **UI chrome:** merge arrows toggle (item 4); Log tab (item 5).

## TESTING / SAFETY
- Anything that writes or scrubs CSVs: test on a **copy** first; verify sums before/after. `token_usage.csv.bak`
  exists; make a fresh backup before any destructive run.
- Verify each item against its **Verify** line above.
- Do not regress the dormant retention ladder, the dynamic defaults, or the /usage proxy token safety.

END OF DRAFT PROMPT.
