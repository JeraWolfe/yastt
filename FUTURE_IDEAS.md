# FUTURE_IDEAS.md — YASTT

Parking lot for features that are not on the formal roadmap but might be worth revisiting later. Adding something here is NOT a commitment to build it.

Format: one section per idea. Each entry has functional description, motivation, and a one-line "why not yet" note.

---

## MeatTime / GridTime tracking

**Status:** Logged 2026-06-08. Requested by Jera during a GML-ULTRACODER session. **Not yet on roadmap.** Currently deferred — the GML-ULTRACODER status line displays `GT-ComingSoon` as a placeholder while the full implementation is parked here for later.

### Definitions (locked after three rounds of clarification with Jera 2026-06-08)

**MeatTime (MT)** — the wall-clock duration of the assistant's process during a turn. Concretely, the value the Claude Code CLI displays in the `Generating…` indicator (e.g., `2m 27s`). From when the assistant begins processing the user's message until the final output is emitted. Excludes Jera's reading/deliberation time. Excludes idle gaps between exchanges. **The CLI timer IS the MT measurement.**

**GridTime (GT)** — estimated time a human coder would take to do the equivalent work the assistant just performed. Human-equivalent work-time, in hours/minutes. NOT processing time. NOT compute time. The labor-substitution figure: "if a human were sitting at this keyboard doing what the agent just did, how long would they need?"

**The metric that matters: the ratio GT/MT.** This is the productivity multiplier the agent delivered on the turn.
- Ratio of 1× → no compression. Agent isn't saving you time.
- Ratio of 10× → an hour of human work in 6 minutes wall.
- Ratio of 100× → an hour of human work in 36 seconds wall.
- Ratio of 1000× → trivial-to-agent task that would take a human all day (rare; usually means parallel subagents covering broad surface).

Tracked over time, the ratio surfaces:
- Productive sessions vs stuck-in-low-leverage-territory sessions
- When tactics should change (sustained low ratio = consider a different approach)
- Real value delivered, distinct from token cost or wall-clock cost

### Why this was logged here (not built tonight)

The GML-ULTRACODER status line was updated 2026-06-08 to compute MT from transcript timestamps (reliable, automated) and read GT from a state file at `~/.claude/last_gt.txt`. The GT state file required the assistant to write its estimate at the end of each turn. **Jera dropped that approach the same night** because:
1. Estimation overhead per turn was cognitively expensive for the assistant
2. Estimates were unreliable (the assistant has no ground-truth signal for "what a human would take")
3. Stale-state risk: if the assistant forgot to write, the status line showed the previous turn's GT
4. The work belongs in YASTT proper, where GT can be tracked with persistence, history, and possibly calibration data — not in an ad-hoc PowerShell state file

The status line now shows `GT-ComingSoon` as a placeholder until YASTT implements the real version.

### What it would do (when built in YASTT)

- Track **MT** — read from transcript JSONL (timestamp delta: most recent user message → assistant final message of that turn). Already available — `cwatch.js` reads similar fields.
- Track **GT** — estimated human-equivalent work hours. See "Data sources" below for proposed estimation approaches.
- Surface both metrics in the YASTT dashboard alongside the existing token-delta and context-total charts.
- New columns on `token_usage.csv`: `MT_ms` and `GT_estimated_ms` per row, alongside `TokenDelta` / `TokenTotal` / `Percentage`.
- New chart on the HTML dashboard: MT per exchange + GT estimate per exchange. **The ratio (GT/MT) plotted over time IS the productivity-multiplier curve.**
- Aggregate stats: average ratio per session, average ratio per day, peak ratio, ratio percentiles.

### Time format (per Jera's convention)

- MT displayed as `HH:MM.SSh` — military hours:minutes.hundredths-of-minute, suffix `h`.
- GT displayed as `HH:MM.SSh` — same format. (Earlier draft used `ms` suffix; corrected because GT is human hours, not milliseconds.)
- Stored in CSV as raw milliseconds for precision; formatted on render.

### Motivation — what GT/MT tracking answers

- "How much human-coder time is this agent saving me per exchange?"
- "Is the agent's productivity-multiplier still high or has the work shifted toward tasks the agent isn't compressing much?"
- "Where is wall-clock MT going — agent execution, agent waiting (subagent dispatch latency), or my own deliberation?"
- "What's the right turn-of-day to push hard on agent work vs do focused human work?"
- "Did this session deliver real value or was it busywork dressed up as progress?"

The GT/MT ratio is the *visible* value of agent-driven work. Token cost is one dimension; wall-clock cost is another; **the ratio is what tells you if the work was actually worth doing this way**.

### Data sources for MT

- Timestamp diff between user-prompt arrival and assistant-response completion. Available in the JSONL transcript that YASTT already monitors via `cwatch.js`. Each `type: "user"` entry has a timestamp; each `type: "assistant"` entry has a timestamp. The delta from a user entry to the immediately following assistant entry is MT for that turn.
- Edge case: subagent durations are NOT separately included in MT, because the parent assistant is "running" during subagent dispatch (the CLI timer keeps ticking). MT subsumes them. Good — the user sees one MT number that reflects total wall-clock cost.

### Data sources for GT (the hard part — multiple options to evaluate)

1. **Assistant self-estimate per turn (the approach attempted tonight, dropped).** Assistant writes its estimate to a state file at end of each turn. Pros: assistant has the richest context for what the work was. Cons: cognitive overhead, no ground truth, stale-state risk if forgotten, no calibration over time.

2. **Heuristic from observable signals.** Compute GT from a formula like `GT_est = f(output_tokens, tool_calls_count, subagent_minutes_summed, file_writes_count, file_reads_count)`. Calibrate the formula against a small hand-labeled training set. Pros: deterministic, repeatable, no per-turn assistant burden. Cons: imperfect (different tasks compress differently — a 500-line refactor is more human work than a 500-line dump-listing).

3. **User-corrected calibration.** Show a draft GT estimate after each turn (or in a periodic review). User confirms or adjusts. Build up a calibration dataset over time. Pros: improves accuracy session over session. Cons: requires user interaction.

4. **Task-category lookup table.** Tag each turn with a task type (research, code-write, debug, refactor, plan, review, etc.). Maintain a per-category "average human time per unit of agent output." Multiply. Pros: clean abstraction, transparent. Cons: requires task tagging (could be automated by inspecting tool-call patterns + assistant output).

5. **Hybrid (likely best).** Use a heuristic as the baseline estimate (option 2), allow optional user override per turn (option 3), and feed user overrides back to recalibrate the heuristic over time. Tag tasks for slicing the data (option 4) so dashboards can show "GT/MT ratio by task type."

### Implementation notes

- Update `token_usage.csv` schema: add `MT_ms`, `GT_estimated_ms`, optionally `task_tag`. Existing CSV reader needs schema-version handling so old rows (no GT) gracefully show "—" rather than crashing.
- Update `cwatch.js` to compute MT from transcript and append to CSV per turn. Already has transcript-watching logic.
- Update the C-Bucks-generated HTML to render the two new charts (MT line, GT estimate line) plus a ratio chart on top.
- Update the `/tokentracker` skill prompt to instruct C-Bucks to render MT/GT alongside existing charts and include a "ratio of the day" callout.
- Consider exposing the most-recent-turn MT and GT in the `cwatch` live dashboard at `localhost:8765/token_usage.html` (alongside the current token-fill bar).
- For the GML-ULTRACODER status line integration: once YASTT writes GT to a known location per turn, the status line script can read it instead of the current `last_gt.txt` placeholder.

### Why not yet

- Current YASTT focus is on token telemetry; time-axis tracking is a separate metric requiring schema work + new charts + heuristic calibration
- The GT estimation approach is genuinely hard and warrants design time, not a quick hack. Several reasonable approaches exist (above) and choosing among them is a real decision.
- Worth revisiting once Jera reviews the GML-ULTRACODER session that generated the request. He plans to come back to YASTT shortly after Phase 1 of GML-ULTRACODER ships.

### Open design questions for when this gets built

1. Which GT-estimation approach (or hybrid)? Pick one to start; iterate.
2. Task tagging: automatic (pattern-detect from tool calls) or manual (assistant declares per turn)?
3. UI: same dashboard or a separate "productivity" view?
4. Aggregation windows: per-turn, per-session, per-day, per-week — all? Different views needed?
5. Calibration: is the goal a personal calibration (Jera's pace) or generalizable across users? Affects whether ground-truth data is collectable.

---
