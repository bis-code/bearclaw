# User-scope Claude Code context

<!-- Genericized twin of the private claude-setup CLAUDE.md (2026-08 diet:
always-loaded context is size-guarded by scripts/test-all.sh; provenance
lives in HTML comments, stripped from loaded context). Personalize the
Identity section for your own accounts/paths. -->

## Identity & git

- Fill in your own accounts and repo locations here — nothing in this repo
  reads this line, so it is documentation for the model, not configuration
- Use conventional-commits (`feat(scope): ...`)

## Code Search

Structural questions (what connects X to Y, who calls/uses Z, module shape)
→ graphify's `query_graph`/`shortest_path`/`get_node` when the MCP tools are
available (see `.mcp.json` — the rebuild is opt-in, never automatic). Literal
text/symbol lookup → `Grep`/`Glob` (live filesystem, always current). Broad
multi-location sweeps needing only a conclusion → dispatch the `Explore` agent.

## Friction-loop awareness

Same constraint/question/symptom in 2+ consecutive user turns: stop. Invoke
`superpowers:systematic-debugging` (or `incident-debugger` for runtime issues)
and run hypothesis → test → decide.

## Effort level

Default `auto` (settings.json) — the harness scales per call and stops subagent
fan-outs spawning at high effort; the main quota lever. `/effort high` for a
single hard session, never as the default.

## Memory

**Verify any structural claim from memory before citing it** — one cheap check
(`ls`/`git log -1`/`gh api`/`grep`). Full discipline: `rules/memory-hygiene.md`
(path-scoped: loads when memory files are touched).

## Response & execution discipline

Surgical diffs, distrust confident output, simplest-first, house style:
`rules/response-discipline.md`. Scope-discipline, verify-before-reference,
confirm-before-implement: `rules/execution-discipline.md`. Both load every
session. Verify outcomes **through the running app/system** when one exists —
a passing build is not a verified behavior.

## Starting a new feature

New feature worktree session (not a handoff continuation): invoke
`superpowers:brainstorming` before writing code — naming/shape disagreements
are cheapest before code exists.

## Long sessions & handoff

Invoke `handoff` before stepping away or when the context warning fires —
`hooks/stop-handoff-reminder.sh` measures exact context from API usage and
warns at 60%, escalating at 70% (the band resets after a /compact). **Never
let auto-compaction be the first context-management event.**
`/handoff-autonomously` = handoff + a `/goal` line (via `goal-prompt`).

## Conversation Pacing

Multiple questions/decisions/trade-offs: **one at a time** — ask, wait, lock,
next. Never bundle into one multi-part message (exception: the user asks for
the full list). Verdicts over a list are mechanized by the `walkthrough` skill.

## Model Selection (for Agent / sub-agent dispatch)

**MANDATORY: set `model:` explicitly on every Agent/Task call** — omitting it
inherits the spawner tier. Tier table + meta-rules: `rules/model-selection.md`.

## Agents

User-scope agents in `agents/` (symlinked via install.sh): `language-reviewer`
(Go/Java/Python/C#/TS — detects language + framework from the diff),
`architect-reviewer`, `performance-reviewer`, `build-error-resolver`,
`incident-debugger`. Per-repo agents shadow user-scope ones — domain-tuned wins.

### Dispatch routing

**Before `general-purpose`, scan the full roster** — user-scope (above),
plugin agents, built-ins (`Explore`, `claude-code-guide`, `Plan`). GP is the
last resort. The trigger→suggestion map lives in
`hooks/pretooluse-dispatch-gate.sh` (denies a matched GP dispatch
once/session) — keep the hook and this roster in sync. Retired-agent surfaces
map to: diff review → `/code-review` · security pass → `/security-review` ·
plan → native plan mode / `Plan` · TDD → `superpowers:test-driven-development`
· dead-code cleanup → `refactor-clean` skill · doc sync → in-session edits.

## Skills

User-maintained: `editing-pr-descriptions`, `handoff` (+ autonomous mode as
`/handoff-autonomously`), `goal-prompt`, `walkthrough`,
`monthly-setup-audit` (includes the context-budget lane), `contract-audit`,
`roadmap`, `address-review-comments`.

Plan-execution chain: `superpowers:writing-plans` → `superpowers:executing-plans`
(≤5 small tasks) or `superpowers:subagent-driven-development` (3+ independent
workstreams). Don't leave a plan dangling.
