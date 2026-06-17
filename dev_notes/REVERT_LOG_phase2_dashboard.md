# REVERT LOG — Phase 2 Dashboard Overhaul

**File touched (only):** `server/token_usage.html`
**Baseline commit (revert target):** `8565981`
**Date:** 2026-06-17
**Agent:** cold write-agent (Phase 2 dashboard)

## Revert command (restores the whole file to baseline)

```
git checkout 8565981 -- server/token_usage.html
```

That single command reverts ALL eight items at once (every change below lives in that one file).

---

## Per-item summary of changes

### Item 1 — Isolate sessions (break the line at session boundaries) — DONE
- `makeAllModeChart` and `makeSingleModeChart`: the `segment.borderColor` callback now returns
  `'transparent'` when the segment's two endpoints (`pts[p0]`, `pts[p1]`) have different `session`
  values, so each session is an isolated trace. Points are unchanged; only the cross-session
  connector stroke is removed. Applied in BOTH color modes and every raw-pip view.

### Item 2 — FULL view shows real full history — DONE
- `displayRows` FULL branch: still aggregates weekly + merges `weeklyTier`, but when live pips span
  < 2 billing weeks the live portion re-aggregates at the finest grain that yields a legible (>=2
  point) series — daily, then hourly, then per-pip (identity bucket) — with the weekly archive
  prepended. Cumulative totals are re-run across the merged ALL series.
- `windowBounds` FULL branch: when live data spans < 2 weeks and there is no weekly archive, the
  window tightens to the real data span (padded) so the fine series FILLS the view instead of
  collapsing to a single far-left dot.
- Added helper `dayStart(ms)` (local-midnight bucket) near `hourStart`.
- Verified: 5-point synthetic single-day dataset renders a 5-point cumulative series (1000..10500),
  not one dot.

### Item 3 — Agents chart → horizontal Gantt bars — DONE
- `parseAgentCSV`: reads `Duration` at index 10 (`duration`, default 0).
- `renderAgentChart`: rebuilt. Custom `ganttBarsPlugin` draws each agent as a HORIZONTAL bar:
  x-extent = `[start, start + duration]` (length = time used), THICKNESS proportional to
  `ContextFill` (totalTokens). Color by `parentWho` (WHO_COLORS); DESK bars get a triangular cap
  at the leading edge (CLI stays a plain bar) — mirroring the top chart's shape convention.
  The x-axis is aligned to the TOP chart's `windowBounds()` `[min,max]` and overlays the SAME
  `buildMarkers` 5h/compact annotations. Custom hit-tested tooltip (`agentBarMouseMove`) replaces
  the native scatter tooltip (no native points exist). Re-renders on window change
  (`setTimeWindow`, `toggleWindowsBack`, `fetchUsage`).
- NOTE: the producing hook must append the `Duration` column for bar LENGTH to be meaningful; old
  rows default to 0 and render as a minimum-width sliver (still visible). The DASHBOARD side is
  complete.

### Item 4 — Merge window arrows into one toggle — DONE
- HTML `#windowsback-toggle`: two buttons replaced by a single `#btn-wb-toggle` calling
  `toggleWindowsBack()`.
- `expandWindow(delta)` removed; replaced by `toggleWindowsBack()` which flips `windowsBack` 0<->1
  and reflects state via the button's `active` class. `setTimeWindow` resets the button visual on
  window change. Week/5h-only visibility rule preserved.

### Item 5 — Log tab — DONE
- HTML: added a `Log` tab LAST in the tab bar (`#tab-log`, not default-open) + a `#log-container`
  with a `#log-table`; added `.log-container`/`.log-table` CSS.
- `setTab` extended: 'log' hides the chart container + all chart toggles, shows the scrollable
  table, and restores the chart on switching back to Tokens/Cost/Cache.
- `renderLogTable`: renders every exchange NEWEST-FIRST (reverse a copy; storage order untouched),
  columns = time, session, who, model, delta, total, cost, cache, compact flag.
- `fetchLog`: polls `yastt_log.csv` (reuses `parseCSV`, identical schema); 404/empty -> `[]`,
  no error. Falls back to `allRows` until the master log exists. Wired into the 10s poll +
  initial load.

### Item 6 — Compact re-derivation (dashboard side) — DONE
- `deriveCompacts(parsed)` (called inside `parseCSV`): walks each session+model thread in clock
  order and sets `r.isCompact = true` only when a row's total dropped below the previous
  SAME-session-AND-model total. Rows with no prior same-thread row fall back to the stored `'C'`
  flag.
- `buildMarkers` compact lines now key off `r.isCompact` (not `r.flag === 'C'`).
- `updateStats` Compacts stat now counts `r.isCompact`.
- Verified: cross-session interleaving with a negative cross-thread delta produces NO phantom
  compact; a genuine in-thread context drop is the only flagged row.

### Item 7 — Session<->Model color toggle + client marker SHAPE — DONE
- HTML `#colormode-toggle`: buttons changed from Session/5h-Block to Session/Model
  (`#btn-session`, `#btn-model`). Visibility rule changed from `whoFilter !== 'all'` to
  `isRawView()` everywhere (`setTimeWindow`, `setWhoFilter`, `setTab`, `syncWindowButtons`), so the
  toggle is available in raw views REGARDLESS of who filter.
- Model-mode color: `MODEL_HUES` + `modelHue` assign each model family a base hue in first-seen
  order; `recomputeModelShades(visibleRows)` builds a per-(family,session) shade index over the
  CURRENT VISIBLE WINDOW (called each render in raw views); `modelColor(r)` returns an HSL shade of
  the family hue varying lightness (38->72%) + saturation (85->50%) together across the model's
  sessions.
- `rowColor` extended with a 'model' branch (and retains 'session' default; legacy '5h' branch
  kept harmless).
- `setColorMode` updated (model button, calls `makeChart()` so it applies in both all-mode and
  single-mode).
- Marker SHAPE: `whoPointStyle(who)` (CLI=circle, DESK=triangle) applied via per-point `pointStyle`
  on the top chart (both modes) and via the DESK triangular cap on the agent bars. `render`
  in-place update copies `pointStyle`.
- `updateLegend`: added a model-mode legend (one swatch per family + "shades = sessions") and a
  "● CLI ▲ DESK" shape key in raw views.
- Tooltip: model name already shown in both modes via `baseOptions` `afterBody` (`model: ...`).

### Item 8 — All-time total cost in the 7D expansion panel — DONE
- `updateAllTimeCost()`: sums cost over the master log (`logRows`) + the weekly archive
  (`weeklyTier`); falls back to `allRows` pip costs until `yastt_log.csv` exists. Stored in
  module-level `allTimeCost`.
- `renderModelRow`: appends an "All-Time Cost" tile inside the expanded 7D panel
  (`$allTimeCost.toFixed(2)`), independent of window and all filters.
- Refreshed on `fetchLog`, `fetchAndRefresh`, and `fetchTiers`.

---

## Items NOT fully implemented

None on the dashboard side. All 8 items are complete in `server/token_usage.html`.

**Out-of-scope dependency (parallel hooks phase, NOT this agent):** Items 3/5/6/8 have producing-side
counterparts in the hooks (`subagent_stop` Duration column; `token_log` writing `yastt_log.csv`;
the hook-side same-session+model compact guard). Those were explicitly out of this agent's scope
(edit ONLY `server/token_usage.html`). The dashboard handles their absence gracefully:
`yastt_log.csv` 404 -> empty log/fallback; missing Duration -> 0; phantom stored flags are ignored
in favor of dashboard re-derivation.
