# Catch Up With The C-Bug Alters

**From:** A C-Bug alter operating on current Jera-Cbug methodology (2026-06-17).
**To:** Any C-Bug alter still operating on ultraplanner-only methodology or pre-V.E.L. file conventions.
**Purpose:** Bring your workflow up to date with current operational doctrine. This file is a bundle of templates — Verification Echo Loop (V.E.L.), file structure conventions, SCRATCH closeout procedures, Gate 2 protocol, halt-and-report doctrine. Take what applies to your project; ignore what doesn't.

---

## Template 1: VERIFICATION ECHO LOOP (V.E.L.) — the upgrade from ultraplanner

### Why this exists

Ultraplanner (C-Brain in the cloud) is unreliable and requires GitHub access. It can't see your in-progress local work. It drifts mid-plan. It's slow. For prompt-validation work it's overkill — we don't need a plan, we need a cold reader who flags ambiguity in our dispatch prompts before the actual agent runs against them.

V.E.L. solves that. Cold-reader agents run **locally** via the Agent tool (general-purpose subagent). No GitHub. No C-Brain. Fast turnaround. They have no warm context, which is exactly the point — they read your prompt fresh, and if it's ambiguous to them, it'll be ambiguous to whatever agent you dispatch with it.

Use ultraplanner for big multi-stage architectural plans. Use V.E.L. for prompt validation before every high-stakes agent dispatch.

### The V.E.L. cycle

```
You author dispatch prompt
  ↓
You (C-Bug Gate 1): self-review for drafting mistakes; surface judgment calls
  ↓
Jera Gate 2: explicit approval to dispatch the V.E.L. cold-verifier
  ↓
Dispatch general-purpose subagent with NO prior context, instruction to read the prompt cold
  ↓
Subagent writes a Comprehension Test report: regurgitation + MUST/WORTH/SKIP findings + verdict
  ↓
You read the report; categorize findings
  ↓
Patch (vN.1) or rewrite (vN+1) per the amended V.E.L. lock (see below)
  ↓
Repeat cycle until DISPATCH-READY
  ↓
Jera Gate 2: explicit approval to dispatch the ACTUAL execution agent
```

### Severity tags

- **MUST** — Structural gap, contradiction, missing file reference, factual error, instruction that cannot be acted on. Blocks dispatch.
- **WORTH** — Nuance gap, tighter wording opportunity, edge case worth covering. Doesn't block; should be folded.
- **SKIP** — Stylistic preference, polish. Logged for completeness; not actioned.

### Verdict semantics

- **DISPATCH-READY** — Zero MUST, no halt-and-report triggers. The prompt is ready to send to the execution agent.
- **NEEDS-PATCH** — Zero MUST but at least one WORTH that meaningfully affects output quality. Surgical patch to vN.1, then dispatch.
- **NEEDS-REWRITE** — At least one MUST. Either cold rewrite to vN+1 (if prompt body is small) OR surgical rewrite (if prompt body is large; see amended lock below).

### The amended V.E.L. lock (2026-06-17)

- **MUST findings → rewrite track.** Cold rewrite OR surgical rewrite of the affected sections. Surgical is preferred when prompt body is large and cold-rewriting risks introducing new mistakes (the "fresh prose = fresh mistakes" anti-pattern).
- **WORTH/SKIP-only findings → patch track.** vN.1 patch with all WORTH+SKIP folded. No follow-up V.E.L. cycle on patches (avoid cycle spiral).
- **0 findings → ship.** vN as-authored is dispatch-ready.

The doctrine: don't keep iterating when the count is stalled at low numbers (3-5) for 2+ cycles AND each new cycle produces findings the previous cycle missed. That's the natural-language asymptote. Beyond it, you're polishing forever without correctness gain. Dispatch.

### How to dispatch a V.E.L. cold-verifier

Use the Agent tool with `subagent_type: general-purpose` and `run_in_background: true`. The prompt for the cold-verifier should look like this skeleton:

```
You are a cold-reader running a V.E.L. cycle on a prompt. NO prior context.
Read the prompt fresh, regurgitate what you understood, surface every
structural gap / contradiction / ambiguity.

Severity tags:
- MUST: structural gap, contradiction, missing reference, factual error, instruction that cannot be acted on.
- WORTH: nuance gap, tighter wording, edge case.
- SKIP: stylistic.

Read fully: <ABSOLUTE PATH TO THE PROMPT FILE>

You may consult to verify references:
- <list of paths the prompt mentions>

Write report to: <ABSOLUTE PATH FOR THE COMPREHENSION TEST FILE>

Structure: Regurgitation, MUST findings, WORTH findings, SKIP findings,
verdict (DISPATCH-READY / NEEDS-PATCH / NEEDS-REWRITE).

Return one line: `<sprint name> V.E.L. complete. Verdict: <X>. Findings: M MUST, W WORTH, S SKIP. Report: <report path>`
```

For multi-prompt batches, dispatch all V.E.L. agents in parallel using multiple Agent tool calls in one message. They run concurrently in background; you get a notification per agent as each lands.

### Naming convention for V.E.L. artifacts

- Dispatch prompt files: `<NAME>_PROMPT.md` (v1.0), `<NAME>_PROMPT_v1.1.md`, `<NAME>_PROMPT_v2.md`, etc.
- Comprehension test reports: `COMPREHENSION_TEST_<NAME>.md` (cycle 1), `COMPREHENSION_TEST_<NAME>_v1.1.md` (cycle 2 on v1.1), etc.
- Multi-reader independent verification: `COMPREHENSION_TEST_<NAME>_reader_a.md` and `_reader_b.md` for cross-checking.

Always keep prior versions on disk. Don't delete v1 when authoring v2. Recovery anchor = git commit + on-disk historical reference.

---

## Template 2: GATE 2 DOCTRINE

Every external-effect action needs its own explicit Jera greenlight. Per-checkpoint, not workflow-blanket.

### The two gates

- **Gate 1: C-Bug.** Self-review. Find drafting mistakes. Fix what's a drafting issue; surface what's a judgment call.
- **Gate 2: Jera.** Read. Confirm. Explicitly authorize.

"Plan looks clean" from C-Bug is NOT execution permission. "Looks good" from Jera on a review is NOT execution permission. Execution permission is an explicit instruction: "go", "execute", "do it", "ship it", "Gate 2 open", "safeties off."

### Where Gate 2 fires

Examples of actions that need their own explicit Gate 2:
- Dispatching any agent (V.E.L. cold-verifier OR execution agent — both need separate gates)
- Writing files to disk in another repo
- Running a build that modifies persistent artifacts
- Copying files to a ship destination
- Deleting source files (even with recovery anchor)
- Committing or pushing to git
- Network calls
- Anything irreversible

When Jera says "I will open it explicitly" — that means: don't auto-dispatch on the back of a previous Gate 2; wait for fresh explicit instruction every time.

---

## Template 3: FILE STRUCTURE CONVENTIONS

### Top-level project layout (generic)

```
<project>/
├── reference/              ← source-of-truth data (markdown, JSON, configs)
├── devtools/               ← C-Bug operational files (soulfiles, plans, scratch)
│   ├── GHOST.md            ← who you are, project context (read first at session start)
│   ├── PICKUP.md           ← current session state, next action
│   ├── RESPAWN.md          ← read FIRST after compact, current state
│   ├── PLANS/              ← planning artifacts (per-phase backlogs, decisions)
│   ├── SCRATCH/            ← temporary files (clipboard images, scratch work)
│   └── claudejeraconvohistory.txt  ← session history
├── SCRATCH/                ← project-root scratch (same rules as devtools/SCRATCH/)
└── (project files)
```

Projects with multi-agent pipelines tend to grow a subdirectory under `devtools/PLANS/` for pipeline artifacts (dispatch prompts, comprehension test reports, integration reports, etc.). Pick a name that fits the pipeline (`HARNESS_SCOPE/`, `PIPELINE/`, `AGENTS/`, etc.) and use it consistently.

### Soulfiles

- **GHOST.md** — identity. Who am I (C-Bug), who is Jera, what is this project, what is the current high-level state. Read at session start.
- **PICKUP.md** — current state, what's pending, what's the next action. Read by current session.
- **RESPAWN.md** — post-compact survival doc. Read FIRST after a context-compact. Has the "immediate next move on wake" recipe.

### The "Current State" pattern in PICKUP.md and RESPAWN.md

Append a new "Current State" block at the TOP every time the state changes meaningfully. Preserve prior blocks below as historical context. Soulfile protection doctrine: **never delete soulfile data without explicit permission.** Add new state on top; old state goes below.

### Pipeline files (generic naming for multi-agent dispatches)

For multi-agent pipelines (V.E.L. + execution + verify chain):

- `<SPRINT>_PROMPT.md` — initial dispatch prompt
- `<SPRINT>_PROMPT_vN.M.md` — evolved versions
- `COMPREHENSION_TEST_<SPRINT>_vN.M.md` — V.E.L. cold-verify reports
- `<SPRINT>_REPORT.md` — execution agent output report
- `<VERIFY>_REPORT_vN_run_M.md` — verification agent runs (preserve prior runs)

---

## Template 4: SCRATCH CLOSEOUT PROCEDURES

### SCRATCH/ rules (per project)

Files in `SCRATCH/` are temporary. They get four possible tag prefixes:

- **`PARK_`** — processed at closeout, parked with a map entry in an archive ledger or equivalent
- **`ARCHIVE_`** — processed at closeout, cold storage in archive
- **`DELETE_`** — cleared explicitly via `/deletables` or hand-removed; NOT auto-cleared
- **`DEFER_`** — survives one closeout (tag stripped on first pass), reviewed again next closeout

**Untagged files at closeout get listed for review. Default is DELETE_.**

### The /clip skill (clipboard capture)

When Jera takes a screenshot with Win+Shift+S and asks you to "check clipboard" or invokes `/clip`, the skill:
1. Captures the clipboard bitmap via PowerShell `[System.Windows.Forms.Clipboard]::GetImage()`
2. Saves it to `<project>/SCRATCH/clipboard_<timestamp>.png` (or with a tag/name if provided as args)
3. Reads the image into your context

The saved file is untagged by default → will be DELETE_ at closeout unless Jera flags it.

### The /deletables skill

Deletes all `DELETE_*` files in `devtools/SCRATCH/`. Run at closeout to clear explicitly-marked files.

### Closeout workflow

At the end of a session or before a meaningful checkpoint:

1. Review `SCRATCH/` contents. List untagged files for Jera's review.
2. For tagged files:
   - `PARK_*` → parked with map entry
   - `ARCHIVE_*` → moved to archive
   - `DELETE_*` → cleared via `/deletables`
   - `DEFER_*` → tag stripped, file survives one more closeout
3. Untagged → default to DELETE_ at next closeout unless Jera explicitly flags.
4. Update PICKUP.md with current state (append at top; preserve history).
5. Update soulfile (RESPAWN.md) with post-compact survival notes if compact may be imminent.
6. Commit if work warrants it (Gate 2 required).

---

## Template 5: HALT-AND-REPORT DOCTRINE

When an agent (V.E.L. cold-verifier OR execution agent) hits a situation where the prompt is ambiguous, contradicts itself, or references something that doesn't exist, the agent should:

1. **Stop the audit/execution.**
2. **Report the contradiction with:** the prompt clause that triggers the halt, the observed conflict, and the proposed clarification the agent would ask the dispatcher.
3. **Do NOT improvise a resolution. Do NOT silently pick an interpretation.**

This applies separately to prompt issues vs. work issues:
- Prompt issues → halt-and-report (the V.E.L. should have caught these; if it didn't, fix the prompt before re-dispatch)
- Work issues (e.g. a specific row in the work list can't be processed) → record per-item failure; continue with other items

The execution agent should distinguish between "I can't do this entire job" (halt-and-report; stop) and "I can't do this specific row" (per-item failure log; continue).

### The "0 halt is informational" finding

When the V.E.L. cold-verifier finds zero MUST findings but flags WORTH/SKIP items, that's not a failure — that's converged-prompt territory. The amended V.E.L. lock says: 0 MUST → ship. WORTHs are improvements you might fold opportunistically; SKIPs are pure stylistic noise.

---

## Template 6: MEMORY SYSTEM

Memory lives at:
```
C:\Users\jeraw\.claude\projects\<project-id>\memory\
```

Where `<project-id>` is the directory-encoded project path (Claude Code generates this automatically based on the project's directory; the encoding replaces path separators with `-`).

### MEMORY.md is the index

`MEMORY.md` is a flat index of memory entries. Each line points at a memory file with a one-line description. Format:

```
- [Short title](filename.md) — one-line summary
```

Read MEMORY.md at session start to load relevant context. Don't read every memory file; grep for ones that match your current work.

### Memory file conventions

Frontmatter:
```markdown
---
name: kebab-case-id
description: one-line summary used by other agents to decide relevance
metadata:
  type: feedback | project | user | reference
---

(body)
```

Types:
- **feedback** — guidance Jera has given on how to approach work; both corrections AND validated approaches
- **project** — ongoing work / goals / initiatives; decays fast, keep current
- **user** — Jera's role, preferences, knowledge; tailors how you collaborate
- **reference** — pointers to external systems (Linear, Slack channels, etc.)

### When to save memory

- User explicitly says "remember this"
- A correction you'd want to know in future sessions
- A validated non-obvious approach
- Project context that can't be derived from code
- External system pointers

### When NOT to save memory

- Code patterns derivable by reading the project
- Recent changes (git log/blame are authoritative)
- Ephemeral task details
- Anything in CLAUDE.md already

### How to update memory

1. Write or edit the memory file.
2. Add or update the line in MEMORY.md.
3. Cross-link with `[[other-memory-name]]` syntax where related.

Treat memory as a living document. Update or remove entries that turn out wrong. Don't accumulate stale memory.

---

## Template 7: PROACTIVE GUIDANCE — what to surface to Jera

### Pink Elephant Protocol

Tell Jera and agents what TO do, not what NOT to do. Saying "don't do X" makes X salient. Reframe negatives as positives.

- Weak: "Don't implement, just stub it."
- Strong: "Write SPECIAL INSTRUCTIONS as a spec for the next agent. Leave stub placeholders in place. Your job ends at the spec."

### AI-native tool advice

Surface proactively when Jera is solving a problem manually that an AI-native tool would solve structurally:
- **MCP plugins** — when work involves a fixed, queryable knowledge domain
- **Skills (slash commands)** — when a repeated workflow pattern emerges
- **Templates** — when the same structural pattern gets written more than twice
- **Memory entries** — when a learned-in-conversation fact would benefit future sessions

Don't wait to be asked. Raise it naturally in context, name the tool, explain in one sentence why it fits, ask if he wants to pursue it.

### No false confidence

Verify before affirming. If unverifiable, say nothing. Don't say "looks good" or "should work" without grounding. Unverified positive framing shuts down Jera's safety process.

---

## Template 8: COMMON SKILLS (slash commands) in current Jera workflow

These should already be registered in `~/.claude/commands/`:

- `/warmup` — read GHOST.md + PICKUP.md + claudejeraconvohistory.txt + git branch at session start
- `/clip` — save clipboard image to SCRATCH (see Template 4)
- `/deletables` — delete all DELETE_-tagged files in devtools/SCRATCH/
- `/cwatch` — start the C-Watch token monitor dashboard
- `/tokentracker` — token-tracker utility
- `/template` — load the project's TEMPLATE.md into context (for project-specific reference)

If your alter's project doesn't have these, they're worth setting up. The `/clip` + `/deletables` pair is especially useful for the visual-workflow loop with Jera.

---

## Template 9: SESSION HANDOFF

At every meaningful checkpoint:

1. Update PICKUP.md (append at top, preserve history).
2. Update RESPAWN.md (full state survival doc for post-compact).
3. Save memory entries for anything learned this session that future sessions need.
4. If git-eligible: commit with descriptive message including session context.
5. If compact is imminent: confirm RESPAWN.md's "immediate next move on wake" is current.

---

## Quick-reference: differences from old ultraplanner-only workflow

| Old (ultraplanner-only) | New (V.E.L. + ultraplanner-as-needed) |
|---|---|
| Send work to C-Brain for plan | Author dispatch prompt locally; cold-verify with V.E.L. before dispatch |
| Requires GitHub access for C-Brain | V.E.L. cold-readers work locally; no GitHub needed |
| Plan iteration via cloud round-trips | V.E.L. iteration is local + fast (1-3 min per cycle) |
| One Gate 2 at plan-approval time | Per-step Gate 2 (every external-effect action) |
| Comprehension on the plan | Comprehension on each dispatch prompt |
| No on-disk audit trail of prompt evolution | Every vN, vN.1, etc. kept on disk + git |
| Ultraplanner does everything | Ultraplanner for big arch plans; V.E.L. for every dispatch prompt |

Use ultraplanner when:
- The work needs cross-system architectural planning (multi-repo, multi-team, multi-phase)
- The plan needs to be reviewed by a peer (C-Brain is your peer)
- You don't have GitHub access concerns

Use V.E.L. when:
- You're authoring a dispatch prompt for an execution agent
- You need fast iteration on prompt quality
- The work is local and doesn't need cloud planning

Combine both when:
- C-Brain authors the high-level plan
- C-Bug breaks the plan into agent dispatches
- V.E.L. validates each agent dispatch prompt
- Jera Gate 2 per step

---

## End of templates

If you're a C-Bug alter reading this for the first time: pick the templates relevant to your project, save them into your local `devtools/` or `reference/`, and update your project's PICKUP.md / GHOST.md to reference the new methodology. Don't try to retrofit every template — take what applies, leave the rest.

Questions: ask Jera. The methodology evolves; if something here is wrong for your project, surface it.
