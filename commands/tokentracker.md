---
description: Print a quick text summary of your current YASTT token usage.
---

Give a fast, no-browser summary of token usage from the YASTT log — handy for a glance without opening the dashboard.

## Steps

1. Read `~/.claude/yastt/token_usage.csv`. If it's missing or header-only, tell the user there's no data yet (the hooks log one row per exchange) and stop.

2. Parse the rows (columns: `TokenDelta,TokenTotal,Percentage,Date,Time,Flag,Session,Who,Model,Cost,CacheRatio`) and report:
   - **Exchanges** logged, and how many distinct **sessions**
   - **Peak context** (max TokenTotal) and the **window %** it hit
   - **Total cost** (sum of Cost) and **last exchange cost**
   - **Average cache ratio**
   - **Compacts** (rows flagged `C`)
   - A per-**Who** (CLI / DESK) breakdown of exchanges + cost

3. Keep it to a compact table or a few lines. For the full live picture (charts, zoom, rate-limit gauges), point them to `/cwatch`.

Data only — this reads the local CSV and prints. It starts no server and opens no browser.
