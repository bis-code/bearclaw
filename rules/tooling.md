# Tooling

<!-- Trimmed 2026-08-16 (S4): the context7 trigger list and Plugins table were
duplicated by harness-injected plugin/MCP instructions — cut (git history has
them). Kept: what the harness does NOT volunteer. -->

## MCP / plugin picks the harness doesn't volunteer

- Architecture decision, schema design, payment/auth flow, multi-module impact
  → `deep-think` — **mandatory when installed**; if absent, reason inline and
  say so once.
- Code search → built-in `Grep`/`Glob` (live filesystem); `Explore` agent for
  broad multi-location sweeps.
- Version-pinned config or framework APIs → verify via `context7` rather than
  training data, and tell dispatched sub-agents to do the same.

## Execution strategy

Pick one **before** editing and announce in one sentence:

| Shape | Skill |
|---|---|
| ≤5 tasks, single concern | `superpowers:executing-plans` |
| 3+ independent coordinated workstreams | `superpowers:subagent-driven-development` |
| Independent problems, no shared state | `superpowers:dispatching-parallel-agents` |
| Sequential work touching auth/payment/credentials, or cross-module refactor | `superpowers:subagent-driven-development` |
| Unsure | `superpowers:executing-plans` |

If 2+ files are in scope: dispatch is mandatory. On a 3rd consecutive direct
`Edit` without dispatch — stop and dispatch.

### Pre-dispatch lane matrix + fan-out economics

Before any **parallel** dispatch, write a one-line-per-lane matrix and announce
it: `| lane | parallel-safe? | write surface | risk |`. Two lanes sharing a
write surface are NOT parallel-safe — sequence them or give each a worktree
(`isolation: "worktree"`).

Fan-out economics (W7): parallelize only when lanes are independent AND each
lane's work exceeds its spawn overhead (~context startup per agent). A 3-file
sequential edit beats a 3-agent fan-out; a 20-file migration or multi-angle
review earns the fan-out. Bound fan-outs (≤2 opus per 5 lanes —
rules/model-selection.md) and state what was NOT covered when capping.

## Hooks can't trigger slash commands

A hook is shell the **harness** runs — not Claude. It cannot invoke a `/skill`
or slash command. "From now on, when X do /Y" must be the hook's own script
logic; if the behavior needs a slash command's *reasoning*, it can't be a hook
— say so instead of wiring one that silently no-ops.
