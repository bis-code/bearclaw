# User-scope Claude Code context

## Project roots

- Set `CLAUDE_PROJECT_ROOTS` in your shell to the space-separated roots you keep
  code under (default `$HOME`). The audit tooling scans these.
- Use conventional-commits (`feat(scope): ...`).

## Code Search

Use `Grep`/`Glob` — they read the live filesystem, so results are always current (no index lag, nothing to build or keep fresh). For broad, multi-location sweeps where you only need the conclusion, dispatch the `Explore` agent instead of running many greps inline.

## Friction-loop awareness

When the same constraint, question, or symptom resurfaces in 2+ consecutive user turns: stop. Invoke `superpowers:systematic-debugging` (or `incident-debugger` if it's a runtime issue) and run hypothesis → test → decide. Don't grind the same answer again.

## Effort level

Default is `auto` (`settings.json` → `"effortLevel": "auto"`) — the harness scales effort per call (mostly medium, escalates for genuinely hard tasks) and, critically, stops subagent fan-outs from each spawning at **high** effort. With the model locked at `opus[1m]`, this is the **main weekly-quota lever** (community-reported >50% reduction). Bump a single hard session with `/effort high` when depth matters; don't make it the default.

## Response discipline

Engineering discipline (surgical diffs, distrust confident output, simplest-first)
and house style (no filler, match length, 2–3 approaches) live in
`rules/response-discipline.md`. Loaded every session.

Your personal persona lives in `rules/about-me.local.md` (gitignored — copy
`rules/about-me.example.md` to create it).

## Execution discipline

How to act on a task — scope-discipline (fix X ≠ touch adjacent code),
verify-before-reference (grep before import, Read-tool before Edit, lockfile
before install), and confirm-before-implement — live in
`rules/execution-discipline.md`. Loaded every session.

## Starting a new feature

At the start of a new feature-branch or worktree session (not a handoff continuation): invoke `superpowers:brainstorming` before writing code. Surfaces naming/shape disagreements while they're still cheap to change. The 4 largest workorder-era sessions that skipped this step accumulated the highest friction-loop counts.

## Long sessions & handoff

Invoke `handoff` (the user-scope skill at `skills/handoff/`) when assistant turns exceed ~250 (lowered from ~400 — June 2026 audit: 44% of context boundaries were still unmanaged compactions), before stepping away >2 hours, or before any session likely to cross a 17 MB / multi-day boundary. Mechanically enforced by `hooks/stop-handoff-reminder.sh`: it measures the **exact** context size from API usage (no longer a bytes heuristic) and warns at **60%**, escalating at **70%**. **Never let auto-compaction be the first context-management event** — every observed auto-compaction in the audit corpus (16/16) erased working memory mid-task and forced re-discovery.

Every `/handoff` ends with a clipboard-ready next-session prompt. `/handoff-autonomously` additionally emits a `/goal` line (via the `goal-prompt` skill) so the next session runs unattended; "give the /goal prompt" alone invokes `goal-prompt` only — no handoff doc.

## Conversation Pacing

When you have multiple clarifying questions, decisions to confirm, or trade-offs to surface: **walk through them ONE AT A TIME**. Ask one question, wait for the answer, lock it in, then move to the next. Do not bundle them into a single multi-part message — large lists are confusing to read and answer, especially on mobile. The only exception is when the user explicitly asks for the full list up front. When the items are verdicts on a list (findings, steps, checklists, reports), this is mechanized by the `walkthrough` skill — one AskUserQuestion card per item.

## Model Selection (for Agent / sub-agent dispatch)

**MANDATORY: set `model:` explicitly on every `Agent` / `Task` call** — omitting it inherits the spawner's tier (silent cost inflation / quality downgrade). Full tier mapping, the 4 meta-rules, and workspace-override policy live in `rules/model-selection.md` (loaded every session).

## Agents

User-scope agents live in `agents/` and are symlinked to `~/.claude/agents/` via `install.sh`:

- **Reviewers (read-only):** `architect-reviewer`, `code-reviewer`, `security-reviewer`, `performance-reviewer`
- **Language reviewers (read-only, on-demand):** `go-reviewer`, `swift-reviewer`, `typescript-reviewer`, `java-reviewer`, `csharp-reviewer`, `python-reviewer` — idiom/concurrency/safety review per language. **Framework-agnostic:** each applies general language rules always and layers stack-specific checks only for what it detects (`java`→Spring/Quarkus/Vert.x; `typescript`→Angular/React/Vue/Node; `swift`→SwiftPM/Xcode; `csharp`→ASP.NET/Unity/.NET; `python`→Django/FastAPI/Flask), deferring version-specific API checks to context7.
- **Implementers:** `tdd-guide`, `refactor-cleaner`, `doc-updater`
- **Planners/debuggers:** `planner`, `incident-debugger`, `build-error-resolver`

Per-repo agents (a `.claude/agents/` dir inside a project) shadow user-scope agents where they exist — domain-tuned wins.

### Dispatch routing

Every agent's description is loaded by the harness. **Before `general-purpose`, scan the full roster** — user-scope agents (above), plugin agents (`feature-dev:*`, `plugin-dev:*`), and built-ins (`Explore`, `claude-code-guide`, `Plan`). `general-purpose` is the **last resort**: name the matched agent in one line first. The full trigger→agent map lives in `hooks/pretooluse-dispatch-gate.sh` (denies a matched-trigger GP dispatch once/session; reminds once when `model:` is omitted) — keep the hook + this roster in sync when adding an agent.

Non-obvious / cross-roster picks: broad codebase search → `Explore` (not GP) · trace how an existing feature works → `feature-dev:code-explorer` · Claude-Code/SDK/API question → `claude-code-guide` · author an agent/skill/hook/plugin → `plugin-dev:*` · review your diff → built-in `/code-review` (effort-scaled) · security pass → `/security-review` · simplify code → `/simplify`.

To add `~/.claude/agents` on a new machine: run `./install.sh` (it handles the symlink).

## Skills

User-maintained skills: `skills/editing-pr-descriptions/`, `skills/handoff/`, `skills/handoff-autonomously/` (handoff + `/goal` line for an unattended next session), `skills/goal-prompt/` (writes a `/goal` condition from the embedded built-in-command docs — models don't know `/goal` natively), `skills/walkthrough/` (item-lists and long reports → one AskUserQuestion card per item, decision log + tracker sync; queues instead of stalling under `/goal`), `skills/agent-self-evaluation/`, `skills/monthly-setup-audit/` (monthly read-only health-check of the whole Claude setup → a risk-grouped report you choose where to save). No orchestrator wrappers remain — natural language + `superpowers:` plus user-scope agents (above) cover the previous ralph/qa surface area.

Plan-execution chain: after `superpowers:writing-plans` produces a plan, the documented follow-on is `superpowers:executing-plans` (≤5 small tasks) or `superpowers:subagent-driven-development` (3+ independent workstreams). Don't leave a plan dangling.
