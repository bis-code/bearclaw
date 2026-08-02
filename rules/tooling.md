# Tooling

When to reach for MCPs, plugins, and skills — guidance the harness doesn't already volunteer through skill descriptions.

## MCP servers

| Need | Tool |
|---|---|
| Architecture decision, schema design, payment/auth flow, multi-module impact | `deep-think` — **mandatory when installed**; if `mcp-deep-think` is not on PATH, reason inline and say so once |
| Code search (concept or exact symbol) | built-in `Grep`/`Glob`; `Explore` agent for broad multi-location sweeps |

## Plugins

| Need | Tool |
|---|---|
| External library / framework docs | `context7` → `resolve-library-id` then `query-docs` |
| Browser automation, UI verification, screenshot capture | `playwright` |
| Whole-feature design before implementation | `feature-dev` |
| Go LSP (definitions, references, types) | `gopls-lsp` (auto-applied) |

### When to reach for `context7`

Use it (don't trust training data alone) when editing or debugging:

- **Version-pinned config**: `docker-compose.yml`, `traefik*.yml`/`traefik*.toml`, `package.json` with non-trivial deps, `pom.xml`/`build.gradle`, `go.mod` direct deps
- **Framework APIs in active use here**: Vert.x verticles/routes/futures, Angular components/RxJS/signals, otelhttp/otelgrpc middleware, koanf providers, sqlx/pgx queries
- **Any library not in the Go stdlib or Java SE/EE base**, when the question is "what's the right shape / what changed in version X"

Sub-agents you dispatch should be told to do this too — name `context7` in the prompt when the task touches the surfaces above.

The `superpowers` plugin's skills are surfaced by the harness with their own trigger descriptions — invoke directly, no mapping needed here. `security-guidance` is passive context.

## Execution strategy

Pick one **before** editing and announce in one sentence:

| Shape | Skill |
|---|---|
| ≤5 tasks, single concern | `superpowers:executing-plans` |
| 3+ independent coordinated workstreams | `superpowers:subagent-driven-development` |
| Independent problems, no shared state | `superpowers:dispatching-parallel-agents` |
| Sequential work touching auth / payment / credentials, or cross-module refactor | `superpowers:subagent-driven-development` |
| Unsure | `superpowers:executing-plans` |

If 2+ files are in scope: dispatch is mandatory. If you catch yourself on a 3rd consecutive direct `Edit` without dispatch — stop and dispatch.

### Pre-dispatch lane matrix

Before any **parallel** dispatch (`superpowers:dispatching-parallel-agents` or a fan-out of `Agent` calls), write a one-line-per-lane matrix and announce it:

| Lane | Parallel-safe? | Write surface | Risk |
|---|---|---|---|
| `<agent / workstream>` | yes/no | `<files or dir it writes>` | `<collision / none>` |

If two lanes share a write surface they are **not** parallel-safe — sequence them, or give each its own worktree (`isolation: "worktree"`). Catches merge-collisions at dispatch time, not at integration.

## Hooks can't trigger slash commands

A hook is shell the **harness** runs (PreToolUse / Stop / Notification / …) — not Claude. A hook therefore **cannot invoke a `/skill` or slash command**. Any "from now on, when X do /Y" automation must be implemented as the hook's own logic (a script that does Y directly), not by calling the slash command. If the behavior genuinely needs a slash command's *reasoning*, it can't be a hook — say so instead of wiring one that silently no-ops.
