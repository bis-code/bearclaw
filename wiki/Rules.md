The `rules/` tier — behavioral instructions loaded into every session — file by file, including the incident that produced two of them.

## What the rules tier is

`rules/` holds the canonical behavioral instructions: how to communicate, how to act on a task, how to spend model tiers, what never to run. Unlike agents and skills, which cost only their description while idle, **every rule file is loaded every session** — which makes this the highest-leverage bucket for context spend, and why the `context-budget` skill flags rule files over 100 lines first.

Rules are prose, so they steer but cannot enforce. Several rules here have a matching hook that mechanizes them, and where that's true the rule file says so in an inline provenance comment naming the evidence that made mechanization necessary. That pairing is the setup's central design idea: **prose for judgment, hooks for the cases where prose measurably didn't work.**

`CLAUDE.md` at the repo root points at these files rather than restating them, so there is one copy of each rule.

| File | Enforced by |
|---|---|
| `response-discipline.md` | `stop-askquestion-nudge.sh` |
| `execution-discipline.md` | `pretooluse-verification-pair.sh` |
| `model-selection.md` | `pretooluse-dispatch-gate.sh` |
| `background-agent-safety.md` | `pretooluse-dispatch-gate.sh` + `guard-destructive.py` |
| `destructive-command-policy.md` | `guard-destructive.py` |
| `memory-hygiene.md`, `git-workflow.md`, `tooling.md`, `solo-project-roadmap.md` | prose only |

## response-discipline.md

How to communicate. The file is deliberately split into two halves **with separate provenance**, and says not to conflate them.

The first half is engineering discipline sourced from Karpathy's public stance on working with LLM coding agents: *optimize the review loop* (small surgical diffs, one concrete change at a time, every changed line maps to the request, don't touch unrelated code); *distrust confident output* (models hallucinate in the same confident register as correct answers, so flag uncertainty and verify before claiming done); *simplest solution first* (no unnecessary abstractions, solve the task in front of you).

The second half is labeled house style and explicitly **not** attributed to Karpathy — the file notes that the viral thread attributes these to him while primary sources do not, records when that attribution was checked, and says to re-check if challenged. Honest sourcing inside a rules file is unusual and worth calling out. Those preferences: no filler openers; match length to complexity; surface two or three approaches before major work; ask via selectable options rather than prose lists; and deal item-lists as cards through the `walkthrough` skill, recognizing the ask in its natural forms ("one by one", "walk me through", "so I can digest") without the user having to name the tool.

The options-not-prose rule is the one with a hook: `stop-askquestion-nudge.sh` blocks once per session when a turn ends with a 2–4 way choice written as prose. The rule file is candid that the hook is only a catch — hooks can't force a tool call, so the rule itself does the real steering.

## execution-discipline.md

How to *act on* a task; the sibling to response-discipline. Every section carries the friction signature that produced it.

**Scope discipline** — "a request to fix X is a license to fix X, not to touch adjacent code." State the affected files before editing; if the fix needs files outside that list, stop and say why. Never remove, hide, or rewrite an existing screen, route, nav entry, entity, field, or endpoint that wasn't named for removal: a bug fix does not delete working features. Unrelated improvements are proposed as follow-ups. This was the most-corrected pattern in the friction audit, across four project groups.

**Dead code — handle, don't ignore** — the deliberate inverse of scope discipline. Scope protects reachable features named for keeping; this removes proven-dead code your own change orphaned. When you create a replacement and the old version becomes unreferenced, removing it *is* part of the change, not a follow-up. But **verify-then-remove**, never delete on a hunch: grep for every reference, then remove and let the build and tests confirm. If reachability is uncertain, it isn't dead — leave it and say why. No `// TODO remove`, no commented-out blocks, no parallel old-and-new implementations.

**Verify before reference** — three high-severity build breaks in one week produced this. Grep to confirm a module, constant, type, function or flag exists before referencing it; don't infer a symbol's name from convention. Before an `Edit`, the file must have been opened with the **Read tool** this session — `cat`, `grep`, `sed`, `head` do not satisfy that contract. Detect the package manager from the lockfile (`pnpm-lock.yaml` → pnpm, `yarn.lock` → yarn, `package-lock.json` → npm, `go.sum` → go) and never run `npm install` in a pnpm or yarn repo.

**Confirm before implement** — for non-trivial UI, ask one question after scope locks: code-spec or design-first? After a domain-model correction, restate the corrected model in one sentence and wait for confirmation rather than silently re-coding against a guess. Treat "make it X-driven" said mid-design as a clarification request, not approval.

**Planning prereq-check** — validate an external prerequisite (a paid API, vendor approval, a billing account, a developer-program membership) is actually reachable *before* planning around it. The provenance: an unmet prerequisite sank 20–30% of one plan.

**Verify source of truth** — local clones, ORM and LSP caches, and hand-maintained files like handoffs and memory are high-staleness. Verify against the live source before acting: reach the actual host before an infra audit, trust `go build ./...` over a language-server cache after a merge, grep real values from code rather than citing a memory entry.

**Verification pairing** — `verification-before-completion` must run before `finishing-a-development-branch`. A required pair, mechanized by `pretooluse-verification-pair.sh` after an audit measured a 20% pairing rate unchanged from the previous month.

**Brainstorm scope-gate** — the anti-ceremony clause. A single field, a styling tweak, or a sub-component with no new data model skips the full brainstorming flow; one design sentence and a thumbs-up is enough. Reserve the full flow for new screens, domain-model changes, and multi-workstream work.

## memory-hygiene.md

The operating discipline for file-based memory: the three tiers and the classification rule, verify-before-citing with a table of one-call verification mechanisms, the two verification checkpoints, writing discipline (one entry one fact, date the verification, link entries, remove on contradiction), `MEMORY.md`-as-index, the anti-patterns, and the full `ERRORS.md` convention with its format, append criteria, and prune rules.

It also justifies its own cost: a typical verification is one shell call, roughly 100ms, while acting on a stale claim costs 30 minutes of re-deciding to days of broken infrastructure.

Summarized in full on [[Memory-System]].

## model-selection.md

How to pick a model when dispatching a sub-agent: the four-row headline table (read/enumerate → haiku, execute → sonnet, reason/design → opus, final gate before an irreversible action → opus), four sticky meta-rules, five dimensions feeding the choice, a list of anti-patterns to refuse on sight, and a policy for project-scoped overrides.

Its provenance comment records the finding behind meta-rule 4: 73% of dispatches went to `general-purpose` despite the written rule, which is why the rule is now backed by `pretooluse-dispatch-gate.sh`. The file also keeps two honest open questions rather than pretending they're settled — whether a deep-think call downgrades the caller's required tier, and whether task records should carry a model field for auditable assignment.

Summarized in full on [[Agents]].

## background-agent-safety.md

The incident file. Quoting the rule's own framing:

> Direct cause of a real 2026-06-08 data-loss incident: a background daemon job ran with `--permission-mode bypassPermissions` AND worktree isolation disabled directly on the live projects tree, then was killed mid-operation by a concurrent CLI self-update. It wiped the projects root, `~/.local`, and shell rc files. No backup existed. Every rule below exists because of that.

The four rules that follow:

1. **Background and daemon agents must run with worktree isolation** so they operate on a throwaway copy, never the live tree. Mechanically enforced: `pretooluse-dispatch-gate.sh` denies a background dispatch without `isolation: "worktree"` once per session, and `guard-destructive.py` is the backstop that blocks the catastrophic delete even when isolation is bypassed.
2. **Don't use `bypassPermissions` for background jobs** that can touch paths above the project root, and keep the destructive-command guard active in all sessions.
3. **The auto-updater must not run while background agents are active** — it deletes the running binary and kills children mid-write. Gate updates on an idle daemon.
4. **Commit or stash unpushed work before starting a background agent.** A throwaway worktree protects the live tree, but a crash mid-run can still cost uncommitted changes in that worktree's copy.

Read this before switching to `bypassPermissions`. The guard hook is a denylist, not a guarantee.

## destructive-command-policy.md

The companion to the incident file: a short, precise statement of what `guard-destructive.py` blocks regardless of permission mode, "because permission prompts alone failed on 2026-06-08."

Blocked: `rm -rf`/`-fr` targeting `/`, `~`, `$HOME`, a bare `$VAR`, `..`, top-level globs, system directories, or any path two or fewer levels under `~`; `git clean -fdx`; `find … -delete` or `-exec rm` over absolute or home roots; recursive `chmod`/`chown` over home or root; redirect-truncation over home dotfiles.

Allowed: narrow project-local deletes like `rm -rf node_modules` or `rm -rf dist` from inside a project. The hook fails **open** on its own errors, so a bug in the guard never blocks legitimate work. Pattern-level detail is in [[Hooks]].

## git-workflow.md

The canonical commit format — a conventional-commit subject, an optional body, then two required trailer lines in a fixed order (`Generated with Claude Code`, then `Co-Authored-By: Claude <noreply@anthropic.com>`), with no robot emoji on the generated line. Types: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`, `security`.

The rules: one logical change per commit; tests pass before committing; **stage specific files — never `git add -A` or `git add .`**; feature branches named `issue/<number>-<short-slug>` from main; one PR per issue; never force-push to main or master. The file declares itself the single source of truth, so a per-project `git-workflow.md` that diverges should be normalized to it.

`settings.json` backs some of this with permission denies for force-pushing main or master, `git reset --hard HEAD~`, and `git clean -fdx`; the confirm gate covers `git push`, `gh pr create`, and `--no-verify` variants.

## tooling.md

When to reach for MCP servers, plugins, and skills — the guidance the harness doesn't already volunteer through skill descriptions. It maps needs to tools (deep-think for architecture decisions, schema design, payment and auth flows, multi-module impact; `context7` for external library docs; the built-in `Grep`/`Glob` and the `Explore` agent for code search), and lists the situations where you should *not* trust training data and must query docs instead: version-pinned config files, framework APIs in active use, and any library outside a language's standard base when the question is "what changed in version X".

Two parts are worth reading even if you skip the rest:

**Execution strategy** — pick one before editing and announce it in a sentence: five tasks or fewer in a single concern → an execution-plan skill; three or more independent coordinated workstreams → subagent-driven development; independent problems with no shared state → parallel agents; sequential work touching auth, payments, or credentials, or a cross-module refactor → subagent-driven development; unsure → the execution-plan skill. With two or more files in scope, dispatch is mandatory; if you catch yourself on a third consecutive direct `Edit` without dispatch, stop and dispatch.

**Pre-dispatch lane matrix** — before any *parallel* dispatch, write one line per lane (lane, parallel-safe?, write surface, risk) and announce it. Two lanes sharing a write surface are not parallel-safe: sequence them, or give each its own worktree. This catches merge collisions at dispatch time instead of at integration.

The file also states a hard architectural fact people get wrong: **hooks can't trigger slash commands.** A hook is shell the harness runs, not Claude, so any "from now on, when X do /Y" automation must be implemented as the hook's own logic. If the behavior genuinely needs a slash command's *reasoning*, it can't be a hook — say so rather than wiring one that silently no-ops.

## solo-project-roadmap.md

Why a solo project needs an external spine: with no PRs, teammates, or reviews imposing structure, state slips between sessions. The durable spine is the project's **GitHub Issues** — distinct from memory (lessons), `ERRORS.md` (failures), a handoff (an ephemeral resume prompt), and a plan (one task). Issues are the living source of truth for what's done and what's next; the others feed it.

The model: `now`-labeled open issues for the one to three in-progress workstreams; `next`-labeled issues in dependency order via "blocked by #N" in the body; closed issues as queryable history; a milestone for a deadline. **No committed `ROADMAP.md`** — issues are read on demand, never auto-loaded every session, because the file this convention replaced grew to 91 KB and taxed every session start.

The discipline: at session start, list the `now` and `next` issues and reconcile them against `git log`, branches, and worktrees, fixing drift first; at session end, close what finished, open or relabel what surfaced, and re-note blockers in bodies. Scope is projects you own and can write to — for a repo you can't write to, defer to its existing tracker and stay read-only. The `roadmap` skill (see [[Skills]]) is the *how*.

## about-me

`rules/about-me.example.md` is a tracked template — role and depth, what you're still leveling up on, communication style, and what to avoid. `install.sh` copies it to `rules/about-me.local.md` if that file is absent, and never overwrites it. The local copy is gitignored, loaded by `CLAUDE.md` when present, and should stay short because it enters every session.

## Adding or changing a rule

Keep it short — it's loaded every session. Record the provenance inline: what evidence made this rule necessary, and when it was verified. And if you find yourself writing a rule that a previous prose rule already covered, that's the signal to reach for a hook instead; see [[Hooks]].
