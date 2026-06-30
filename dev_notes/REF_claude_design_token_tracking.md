# REF — Claude Design (Cmonkey) token-usage tracking for YASTT

**Built:** 2026-06-18 by C-Bug, from web research (no Anthropic API for this product exists yet).
**Purpose:** Answer "can YASTT include Claude Design's token use, e.g. by having Designer return
token counts with its files?" — and record the facts so we don't re-research it.
**Bottom line:** Not per-design today (no API, no local transcript, no usage in its outputs). Its
usage IS already in YASTT's account-wide gauges because it bills against the same subscription.

---

## What Claude Design is (verified facts)

| Fact | Detail |
|---|---|
| Product | **Claude Design** (Anthropic Labs), research preview. Jera's nickname: **Cmonkey**. |
| Access | **Web app only** — `claude.ai/design`. No CLI, no API, no local/desktop component. |
| Model | Powered by **Claude Opus 4.7**. |
| Billing | **Subscription** (Pro / Max / Team / Enterprise). Uses **the same account usage limits** as normal Claude, "with the option to continue beyond those limits by enabling extra usage." No separate API-token pricing. |
| Token/cost display | **None mentioned** in the product UI. |
| Outputs | Export to **Canva, PDF, PPTX, standalone HTML**; save as a folder; share as an internal org URL. |
| Claude Code handoff | A **handoff bundle** = design files + design-system tokens + component structure + per-page intent. **No usage/token metadata in the bundle.** |
| Developer API | **None today.** Anthropic: "we'll make it easier to build integrations with Claude Design over coming weeks." |

---

## Why this decides the YASTT question

YASTT gets per-exchange numbers from **local Claude Code hooks** reading a session's **transcript
JSONL** (the `usage` object per assistant entry). Claude Design runs **in the cloud**, like the
Planner and the browser client — it never touches a local hook and leaves **no local transcript**.
So the local-hook and transcript-ingest paths (the accurate ones for CLI/Desktop) **cannot apply.**

The two ideas from the earlier review, against these facts:
- **Hook it / ingest its transcript** → not possible (cloud, no local artifact).
- **Have Designer return token counts with its files** (Jera's idea) → not possible *from Design*:
  the handoff bundle and the HTML/PDF/PPTX exports carry **no usage data**, and the model can't
  self-report its own true `usage` (same unreliability that killed the GridTime self-estimate —
  see [[FUTURE_IDEAS]] MeatTime/GridTime). There is no wrapper we control around Design to attach
  real numbers, because it's a closed web product.

## What IS already true (the good news)

Because Claude Design **bills against the same subscription**, its consumption is **already counted**
in the data YASTT pulls from the OAuth usage endpoint (`/api/oauth/usage`):
- It is in the **account-wide 5h and 7-day utilization** gauges.
- Since Design runs on **Opus 4.7**, its usage is folded into the **Opus 7-day** per-model bucket
  that YASTT already shows in the expanded 7D panel.

So Design's load is **visible in aggregate today** — you just can't *attribute* a number to Design
specifically, or get per-design / per-exchange detail, because the endpoint reports totals, not a
per-product breakdown.

## What gets captured anyway: the build step

When you pass a Design **handoff bundle to Claude Code** and Claude Code builds from it, **that Claude
Code work fires local hooks and IS tracked by YASTT** (as CLI). So the *implementation* cost is
already in the dashboard. Only the *design-time* cost inside Claude Design is missing per-exchange.

---

## Options, ranked for now

1. **Accept aggregate (do nothing / label it).** Design's tokens are already in the 7D/5h gauges and
   the Opus bucket. Optional tiny change: note in the dashboard that the account gauges include
   cloud usage (Design, Planner, browser), so they read higher than the sum of the local per-exchange
   lines. No new data source needed. **Recommended until an API exists.**
2. **Wait for the promised Claude Design integration / API.** Anthropic has said integrations are
   coming. When an API or a usage export ships, that's the real per-design path — revisit then.
3. **Manual / estimated entry.** Unreliable and high-effort; rejected (GridTime lesson).

## Watch-list (revisit triggers)

- A **Claude Design API** or any documented integration surface appears → re-evaluate option 2.
- The Anthropic **Console Usage & Cost API** ever breaks subscription usage down by product
  (currently it covers API-org usage, not claude.ai subscription products) → possible attribution source.
- Claude Design starts writing a **local handoff artifact** that includes usage, or its exports gain
  usage metadata → ingestable like a sidecar.

---

## Sources

- [Introducing Claude Design by Anthropic Labs](https://www.anthropic.com/news/claude-design-anthropic-labs)
- [Claude Design → Claude Code: AI Design Handoff (claudefa.st)](https://claudefa.st/blog/guide/mechanics/claude-design-handoff)
- [Using Claude Design for prototypes and UX (claude.com)](https://claude.com/resources/tutorials/using-claude-design-for-prototypes-and-ux)
- [What Is Claude Design? (DataCamp)](https://www.datacamp.com/blog/claude-design)
