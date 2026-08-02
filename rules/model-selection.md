# Model Selection (for Agent / sub-agent dispatch)

When spawning a sub-agent via the `Agent` tool, pick the model by task shape. This rule applies to all workspaces unless a workspace's `.claude/rules/` or memory overrides it for a specific task type (e.g., Solidity contract verification, Unity editor scripting).

## Headline rule (4-row TL;DR)

| Task shape | Default model | Don't go below | Override up when |
|---|---|---|---|
| Read / enumerate / extract (recap, file listing, route inventory, grep/glob search) | `haiku` | — | The "extract" needs interpretation, not retrieval. |
| Execute (TDD, refactor, Playwright, CI, doc, PR, issue drafting, test interpretation) | `sonnet` | `sonnet` | The execution path is irreversible, security-touching, or architecture-deciding. |
| Reason / design / synthesize (architecture, security review, audit recommendation, drift taxonomy, design brief) | `opus` | `sonnet` (only if scope is genuinely bounded) | n/a — this IS the high tier. |
| Final gate before irreversible action (merge, deploy, rollout) | `opus` | `sonnet` | n/a. |

## Four sticky meta-rules
<!-- Provenance: F11 — 73% of dispatches were general-purpose (June 2026 audit); rule 4 and matching anti-pattern added to fix this. Enforced by hooks/pretooluse-dispatch-gate.sh (matched-trigger general-purpose dispatch denied once/session). -->

1. **Always set `model` explicitly on Agent calls** — never rely on spawner-inheritance. The team-lead is often on opus, so omitting `model:` silently buys opus rates for sub-agents. Same rule for **Workflow `agent()` calls** (and `pipeline()`/`parallel()` stages): set `model:` on every one — default workflow sub-agents to `sonnet` (sub-agents are the bulk of token spend, so this is the biggest real cost lever), reserve `opus` for the few architecture / review / synthesis agents.
2. **Pick the model for the hardest part of the agent's job and keep it for that agent's lifetime** — never split one job into a haiku-then-opus chain. Each agent pays full prompt-cache startup; the 5-minute TTL makes mid-job swaps costly.
3. **In parallel dispatch, mix models** — target ≤ 2 opus agents per 5-way fan-out; route the rest through sonnet/haiku based on per-task shape.
4. **Set `subagent_type` to the most specific named agent, not `general-purpose`** — when a task matches a named agent (`go-reviewer`, `build-error-resolver`, `planner`, …), dispatch *that* agent: it carries tuned instructions + scoped tools. `general-purpose` is the fallback only when nothing fits. Pairs with rule 1 — still set `model:` explicitly.

## Five dimensions feeding model choice

Pick the cheapest model that clears the highest-scoring axis:

- **Reasoning depth** — hops in working memory
- **Context budget** — working-set size
- **Speed of feedback** — interactive blocks → cheaper model
- **Cost sensitivity** — frequency × duration
- **Error tolerance** — blast radius of a wrong output. The **deciding axis** when low.

## Anti-patterns (refuse on sight)
<!-- Provenance: F11 — see "Four sticky meta-rules" provenance comment. -->

- `opus` for pure file enumeration / recap — use haiku
- `haiku` for architecture, security review, or judgment refactor — use sonnet or opus
- Mixing models within a single sub-agent's lifetime — pick one and stay
- Inheriting the spawner's model by omitting `model:` on `Agent` calls
- `opus` inside a tight `/loop` (cost balloons; the loop almost always wants haiku or sonnet)
- Dispatching `general-purpose` when a named agent fits the task — pick the specific one

## Open questions (resolve per-workspace as evidence accumulates)

1. Does `deep-think` MCP usage downgrade the caller's required model? Hypothesis: yes — a sonnet caller is enough when `deep-think` is the actual reasoner.
2. Should `TaskCreate` carry a `model` field for auditable per-task assignment?

## Workspace overrides

A workspace's `.claude/rules/` or workspace-scoped memory can override these defaults for non-standard task types. Examples:

- Solidity contract verification (no rule yet — likely opus for non-trivial contracts due to gas + reentrancy reasoning)
- Unity editor scripting (no rule yet — sonnet probably suffices; verify with one cycle)

When a workspace overrides, the override stays in workspace scope until at least one fix-cycle confirms the choice. Don't promote workspace-specific overrides back here without that validation.
