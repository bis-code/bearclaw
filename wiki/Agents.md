The 16 named subagents bearclaw ships, how to choose between them, and the model-selection rules that keep sub-agent cost honest.

## What an agent is here

An agent is a markdown file under `agents/` with frontmatter carrying a `name`, a `model`, a `description`, and an `allowed_tools` list. You dispatch one with the `Agent` tool; the harness loads every agent's description, so descriptions are what routing keys off.

Two properties matter when picking one. **Tool scoping**: the read-only reviewers are given only `Read`, `Glob`, `Grep` and `Bash`, so they physically cannot edit your code — they report findings and you decide. Implementers additionally get `Edit` and `Write`. **Stack detection**: every language reviewer detects the project's stack first, applies general-language rules always, and layers stack-specific checks only for what it actually finds, deferring version-specific API questions to `context7` rather than guessing from training data.

A project can also ship its own `.claude/agents/` directory. Per-repo agents **shadow** user-scope agents of the same name — domain-tuned wins.

## Roster

### Reviewers (read-only)

| Agent | Model | Focus |
|---|---|---|
| `architect-reviewer` | opus | Architecture: module boundaries, dependency direction, coupling, pattern consistency. Also granted the deep-think reasoning tools. |
| `code-reviewer` | sonnet | Code quality: analyzes git diffs for correctness, error handling, test coverage, security, and style. |
| `security-reviewer` | opus | Security vulnerabilities: OWASP-focused analysis of code changes and project configuration. |
| `performance-reviewer` | sonnet | Performance: N+1 queries, unbounded results, blocking operations, missing indexes, resource leaks. |

### Language reviewers (read-only, on-demand)

All six are read-only and report findings. Each names the stacks it adapts to:

| Agent | Model | Detects and adapts to |
|---|---|---|
| `go-reviewer` | sonnet | Idiomatic Go, concurrency, error handling, performance. |
| `swift-reviewer` | sonnet | Value semantics, ARC, Swift Concurrency (actors/`Sendable`), protocol-oriented design; project shape (SwiftPM vs Xcode app) and platform (SwiftUI/UIKit/AppKit/server). |
| `typescript-reviewer` | sonnet | Type safety, async correctness, Node/web security, idiomatic patterns; framework detection across Angular, React, Vue, Svelte, Node. |
| `java-reviewer` | sonnet | Framework and build tool detected first (Spring, Quarkus, Vert.x, Micronaut, Jakarta, plain), then general Java rules plus the matching playbook. Covers security, concurrency, resource safety, JPA/N+1, idioms. |
| `csharp-reviewer` | sonnet | Stack detection across ASP.NET Core, .NET library, Unity, MAUI, Blazor, WPF, plain. Covers security, async, concurrency, nullable safety, EF Core, idioms. |
| `python-reviewer` | sonnet | Stack detection across Django, FastAPI, Flask, async, data-science, CLI, plain. Covers security, error handling, async correctness, typing, idioms, N+1. |

### Implementers

| Agent | Model | Use when |
|---|---|---|
| `tdd-guide` | sonnet | Starting new service-layer logic or fixing a bug — writes the failing test first, then guides red-green-refactor. Highest leverage on handlers, service code, and API endpoints. |
| `refactor-cleaner` | sonnet | Removing dead code, deduplicating logic, cleaning unused imports and exports — especially after a feature lands and obsoletes its scaffolding. Verifies each removal with tests before keeping it. |
| `doc-updater` | sonnet | After a feature or schema change, to sync README, OpenAPI specs, inline godoc/javadoc, and CHANGELOG. Updates existing docs only — it does not author new ones from scratch. |

### Planners and debuggers

| Agent | Model | Use when |
|---|---|---|
| `planner` | opus | Before non-trivial implementation work — produces a step-by-step plan with affected files, test strategy, and risks. Especially for cross-module changes, new endpoints, schema migrations. **Plans only, never writes code**: its tool list has no `Edit` or `Write`, only reads plus web search. |
| `incident-debugger` | sonnet | Code compiles but behaves wrong at runtime — a flaky test, wrong response shape, an unexpected 500, a missing trace span, a race condition. Hypothesis-driven, with the deep-think tools available. |
| `build-error-resolver` | sonnet | A build or CI run failed (Go, Java, Swift, .NET, Python, TypeScript, lint). Detects the language and build tool first, applies the matching per-language playbook, reads the actual build output, and fixes root causes with minimal diffs. |

## Dispatch routing

The discipline is simple to state: **`general-purpose` is the last resort.** Before dispatching it, scan the full roster — bearclaw's agents above, plugin agents, and the harness built-ins — and name the matched agent in one line first.

Some picks are non-obvious:

| Need | Dispatch |
|---|---|
| Broad codebase search | the built-in `Explore` agent, not `general-purpose` |
| Trace how an existing feature works | a code-explorer agent from the feature-dev plugin |
| A Claude Code / SDK / API question | the built-in Claude Code guide agent |
| Author an agent, skill, hook, or plugin | the plugin-dev agents |
| Review your working diff | the built-in `/code-review` command |
| Security pass | `/security-review` |
| Simplify code | `/simplify` |

This rule is one of the clearest cases in bearclaw of prose failing and mechanization succeeding. An audit found **73% of 2,443 dispatches went to `general-purpose`** despite the written rule, and a prose-only fix the previous month changed nothing. So the trigger-to-agent map now lives in `hooks/pretooluse-dispatch-gate.sh`, which denies a matched-trigger general-purpose dispatch **once per session** and names the agent it matched. Re-issuing the same call passes — an informed choice, not a lockout. Keep that hook and the roster in sync when you add an agent.

The same gate carries two secondary checks: a once-per-session advisory when `model:` is omitted from a dispatch, and a once-per-session denial of a background dispatch that lacks `isolation: "worktree"` (see [[Rules]] for the incident behind that one). Details in [[Hooks]].

## Model selection

Sub-agents are the bulk of token spend, so which model each one runs is the biggest real cost lever in the setup. The headline table:

| Task shape | Default model | Don't go below | Override up when |
|---|---|---|---|
| Read / enumerate / extract — recap, file listing, route inventory, grep/glob search | `haiku` | — | The "extract" needs interpretation rather than retrieval. |
| Execute — TDD, refactor, browser automation, CI, docs, PRs, issue drafting, test interpretation | `sonnet` | `sonnet` | The path is irreversible, security-touching, or architecture-deciding. |
| Reason / design / synthesize — architecture, security review, audit recommendation, drift taxonomy, design brief | `opus` | `sonnet`, only if scope is genuinely bounded | n/a — this is already the high tier. |
| Final gate before an irreversible action — merge, deploy, rollout | `opus` | `sonnet` | n/a. |

### The four meta-rules

1. **Always set `model` explicitly on Agent calls.** Never rely on spawner inheritance: a lead running on opus silently buys opus rates for every sub-agent when `model:` is omitted. The same applies to workflow `agent()` calls and `pipeline()`/`parallel()` stages — default those to `sonnet` and reserve `opus` for the few architecture, review, and synthesis agents.
2. **Pick the model for the hardest part of the agent's job and keep it for that agent's lifetime.** Never split one job into a cheap-then-expensive chain: each agent pays full prompt-cache startup and the short cache TTL makes mid-job swaps costly.
3. **In parallel dispatch, mix models.** Target at most two opus agents in a five-way fan-out; route the rest by per-task shape.
4. **Set `subagent_type` to the most specific named agent.** A named agent carries tuned instructions and scoped tools that `general-purpose` does not.

When two candidate models both seem defensible, pick the cheapest that clears the highest-scoring of five axes: reasoning depth, context budget, speed of feedback, cost sensitivity, and error tolerance — where error tolerance (the blast radius of a wrong output) is the deciding axis whenever it's low.

### Anti-patterns

Refuse these on sight: opus for pure file enumeration or recap; haiku for architecture, security review, or judgment-heavy refactoring; mixing models within one sub-agent's lifetime; omitting `model:` and inheriting the spawner's tier; opus inside a tight loop, where cost balloons; and `general-purpose` when a named agent fits.

### Workspace overrides

A project's own `.claude/rules/` or project-scoped memory can override these defaults for a non-standard task type. The convention is that an override stays project-scoped until at least one fix-cycle confirms the choice — don't promote it to the global rule without that validation.

## Adding an agent

Write the frontmatter (`name`, `model`, `description`, `allowed_tools`) with a description precise enough for routing to key off, scope the tools to the minimum the job needs — read-only unless it genuinely must write — then add the trigger to `hooks/pretooluse-dispatch-gate.sh` so the gate can steer toward it. The anti-bloat rule applies: if it isn't load-bearing for everyday use, it doesn't ship.
