The 17 skills bearclaw ships, grouped by purpose, with the phrases that trigger each one and what it produces.

## How skills work

A skill is a directory under `skills/` containing a `SKILL.md` with YAML frontmatter — a `name` and a `description`. Only the description is always in context; the body loads when the skill is invoked. That makes the description the real interface: the harness matches your phrasing against it and invokes the skill, or you name it explicitly (`/handoff`). Because idle cost is description-only, a large catalog is cheap — which is why the always-loaded `rules/` tier and MCP tool schemas, not skills, are the levers the `context-budget` skill tells you to look at first.

Most bearclaw skills announce themselves on invocation ("I'm using the handoff skill to capture session state"), so you can tell when one is driving. Some carry supporting files: a script (`visual-companion/generate.sh`), a workflow definition (`monthly-setup-audit/audit-workflow.js`), or reference docs the skill is required to read before acting (`goal-prompt/references/`).

## Session continuity

The core pair is `handoff` + `memory-capture`: one carries *state* to the next session, the other carries *lessons* across many. They complement each other rather than overlap.

### handoff

**Triggers:** "handoff", "continuation prompt", "something to paste into a fresh session", "let's pause", "I need to stop" — or context past roughly 70% full.

**Produces:** a handoff document at `docs/superpowers/handoffs/YYYY-MM-DD-<topic-slug>.md` in the repo, plus a clipboard-ready prompt for a fresh session. The goal it states plainly: a fresh session should be productive within one prompt — no re-exploration, no re-deciding.

Its distinguishing feature is a **gate function** that runs before any writing: `git status`, `git log -5 --oneline`, `git diff --stat`; detect the phase (discover / plan / implement / test / review); scan the transcript for material decisions, unanswered questions and the next command; find the plan file if one exists. Skipping the git step is, in the skill's own words, "writing fiction" — the handoff must reflect actual VCS state, not assumed state.

It also refuses to duplicate a roadmap. When the repo is one you own with a GitHub-Issues roadmap, "What's Next" points at the issues instead of restating them, and the handoff captures only the session delta not yet recorded: uncommitted work, dead ends tried, open questions, decisions not yet written to an issue. It explicitly says **not** to run for one-off questions, completed work with nothing pending, or debugging that resolved cleanly.

### handoff-autonomously

**Triggers:** `/handoff-autonomously`, or asking for a handoff where the next session should continue unattended after `/clear`.

**Produces:** a full `handoff` plus a ready-to-paste `/goal` line — delivered as **two** labeled paste messages, because a slash command only executes at the start of a message and `/clear` wipes any active goal.

Three details are hard-won. The `/goal` line is also appended to the handoff doc itself as an `## Autonomous goal` section, because chat scrollback is lossy — a goal that existed only in chat had to be recovered from a raw session transcript once. Message 1 instructs the goal session to queue human-shaped items rather than deal `AskUserQuestion` cards while a goal is active. And the run ends by appending a structured completion report (Accomplished / Walkthrough queue / Proposed next steps) that the next `walkthrough` deck is dealt over.

### goal-prompt

**Triggers:** "give the /goal prompt", "write a goal for the next session", "what should the goal be" — or as the final step of `handoff-autonomously`.

**Produces:** one `/goal` line, and nothing else when invoked standalone.

The skill exists because `/goal` is newer than most models' training data, so it **requires** reading its bundled reference docs before writing a condition rather than working from memory. The output has a fixed shape: a measurable end state, the stated check whose output proves it (the evaluator only reads the transcript), constraints with their own proofs, a turn bound so a stuck goal terminates, and — the subtle one — an explicit alternate terminal state. A condition whose failure branch merely *describes* stopping is never judged met; one run burned six identical evaluations on an externally-blocked state before that was fixed.

### memory-capture

**Triggers:** "capture this lesson", "bank what we learned", "drain the memory review queue", the SessionStart review nudge, or invocation from `/handoff`.

**Produces:** memory entries written **only** to what you explicitly accept, defaulting to repo-local.

This is where Claude does the distillation the hooks cannot — shell hooks can't call an LLM, so they only stage raw signal. Two entry paths (interactive at handoff time, or draining the queued raw captures) share one middle: distill → dedup → ask → write. High-signal turns flagged by `stop-memory-signal.sh` are distilled first, which fixes candidate dilution in long sessions. Full mechanics in [[Memory-System]].

## Interactive review

### walkthrough

**Triggers:** "one by one", "walk me through", "present the findings with AskUserQuestion", "manual steps", "so I can digest", reviewing what was decided or accomplished, triaging a checklist.

**Produces:** a card deck — exactly one `AskUserQuestion` card per item, one per turn — plus a decision log and tracker sync at the end.

Items are partitioned by type and dealt in a fixed order: **digest → recap → manual/verify → decisions → next steps**. Digest first, because digesting long text is usually where the other item types surface; then the cheap confirms; judgment last. Each type has its own option set (Confirm/Correct for recaps, Done/Blocked/Skip for manual steps, Pass/Fail/Can't check for verifications, 2–4 real trade-offs for decisions, Do now/Defer/Drop/Discuss for next steps). A "Discuss" answer pauses the deck for plain conversation, then re-deals the same card unless the discussion already answered it.

Two boundaries are worth knowing: it operates **only on material already in context** — it is not a resume mechanism and never goes hunting in files for something to walk through — and under an active `/goal` it queues human-shaped items instead of stalling on a card nobody is there to answer.

## Maintenance

### monthly-setup-audit

**Triggers:** asking to audit, review, health-check, or "spring-clean" the Claude Code setup. Intended to run roughly monthly.

**Produces:** a dated, risk-grouped report; then, only after you confirm, the safe and reversible fixes applied.

Three phases. **Collect** runs `scripts/audit-collect.sh`, which gathers deterministic evidence — config inventory, friction signatures, memory integrity, cost and drift — into a temp dir at near-zero token cost, so the analysis agents never touch raw transcripts. **Analyze and synthesize** fans four lane agents out over that evidence and has one high-tier synthesizer write the report. **Apply** is gated on your confirmation and limited to reversible changes. The audit itself is read-only.

### agent-self-evaluation

**Triggers:** before declaring a research, review, audit, design, or synthesis deliverable done.

**Produces:** a five-axis score with cited evidence, and a fix to the weakest axis before the deliverable is returned.

The axes are accuracy, completeness, clarity, actionability, and conciseness. A bare number is not allowed — each score cites evidence from your own output (the check you ran per claim, each part of the request mapped to part of the answer, what you cut). Any axis at 3 or below gets fixed before returning rather than shipped with a caveat, lowest axis first. It also distrusts a straight-5 self-score: name the weakest axis even when every axis passes. It's the complement to verification-before-completion, which verifies code behavior rather than whether the answer is any good. Skip it for trivial turns.

### context-budget

**Triggers:** "context budget", "what's eating my context", "do I have room to add X", or a session feeling sluggish after adding components.

**Produces:** a per-component token estimate plus prioritized savings recommendations. Read-only — it measures and recommends, never removes.

It inventories agents, skills, rules, MCP servers, and the project + user `CLAUDE.md` chain in the active config root, flagging outliers (agent files over 200 lines, skills over 400, rules over 100, MCP servers with more than 20 tools or that merely wrap a CLI). Crucially it resolves symlinks and skips identical copies, so tooling shared across config roots is counted once. Its standing conclusion: agents and skills are on-demand and cost only their description while idle, so the always-loaded levers are `rules/`, `CLAUDE.md`, and MCP tool schemas.

### contract-audit

**Triggers:** "contract audit", "is the app calling routes that don't exist", API drift after backend changes.

**Produces:** a diff of the endpoint sets each layer of a project defines or calls, with `file:line` evidence on both sides.

The engine is generic; everything project-specific comes from a `.contract-audit.yml` descriptor in the target project. Missing or incomplete descriptor means an interview — one question at a time — after which the skill writes the descriptor so the next run skips it. That one write is its only exception to being read-only; it never modifies code, stages, or commits. Its core rule is **never guess**: an ambiguous descriptor or a dynamically-constructed endpoint gets a question or an *Unverifiable* entry, because a confidently wrong audit is worse than a question.

### find-skills

**Triggers:** "how do I do X", "find a skill for X", "is there a skill that can…", or wanting to extend capabilities.

**Produces:** search results from the open agent-skills ecosystem via the Skills CLI (`npx skills find`, `add`, `check`, `update`), and installation guidance.

## Development workflow

### address-review-comments

**Triggers:** "address my PR comments", "address review comments", "handle the review feedback", "do the REVIEW(claude) notes".

**Produces:** one smallest-diff fix per feedback item, worked one at a time. It **never stages or commits** — you review `git diff` and commit yourself.

It handles two feedback sources and detects which mode applies: in-code `REVIEW(claude):` markers found by `bin/claude-review-markers`, and GitHub PR comments found by `gh pr view`. Both present means markers first, then the PR, unless you pick. Neither means it reports "no review feedback found" and stops. In PR mode it verifies the logged-in `gh` account plausibly matches the PR repo owner before acting.

The marker helper is careful in a way worth noting: it matches `REVIEW(claude):` only when the tag follows a comment leader, so the tag quoted in prose or documentation is ignored, and it searches tracked files only, so `.gitignore` is respected. Output is a JSON worklist.

### editing-pr-descriptions

**Triggers:** "update PR description", "rewrite PR body", "fix PR title", or finishing a long-running branch whose original description is stale.

**Produces:** a structured PR body grouped into 3–6 scannable themes, applied with `gh pr edit --body-file`.

It insists on gathering the real change set first — `gh pr view --json` for current state, then `git log --oneline <base>..HEAD` as the source of truth — rather than paraphrasing from memory or recent conversation, because branches accumulate work over weeks. Defaults to a minimal body: no filler sections you didn't ask for.

### roadmap

**Triggers:** `/roadmap`, "set up a roadmap", "what's left on this project", "where are we", roadmap drift after merges.

**Produces:** a project's roadmap as GitHub Issues — `now` and `next` labels, dependency order via "blocked by #N" in issue bodies, closed issues as the queryable history, and a milestone for any deadline.

Four actions depending on state: bootstrap (no labels yet), migrate (still on a committed `ROADMAP.md`), reconcile (starting work), update (wrapping up). Bootstrap gathers real state from `git log`, branches and worktrees, then **shows the planned issues and asks for correction before creating any** — it won't seed a guessed roadmap. Scope is projects you own and can write to; for a repo you can't write to it defers to that project's tracker and stays read-only. The convention and session discipline live in the matching rule (see [[Rules]]); this skill is the *how*.

### visual-companion

**Triggers:** "visual companion", "open as html with notes", "interactive review doc", or a markdown doc containing `### Your notes` subsections waiting for input.

**Produces:** a sibling `.html` next to the source markdown, opened in the browser, where each notes heading becomes an editable textarea. Notes persist in `localStorage` per document and section; the toolbar copies all notes for paste-back to chat, downloads a merged `.md`, or clears everything.

It names its own non-uses: a doc with no notes sections (a plain renderer suffices) and a doc containing secrets or credentials, which would land in `localStorage` where they're harder to clean up than from a file.

## Swift deep-dives

Three reference skills that carry real technical content rather than a workflow — useful as the model's source of truth when the language moved faster than its training data.

| Skill | Triggers | Covers |
|---|---|---|
| `swift-concurrency-6-2` | data-race compiler errors, Xcode 26 migration, "where does this async run", designing MainActor-centric architecture | Swift 6.2 "Approachable Concurrency": single-threaded by default, async staying on the calling actor (SE-0461), `@concurrent` for explicit background offloading, isolated conformances (SE-0470), MainActor-by-default (SE-0466). |
| `swift-actor-persistence` | building an offline-first store or repository, replacing `DispatchQueue`/`NSLock` synchronization, needing concurrent-safe access to shared mutable state | Thread-safe persistence via actors — an in-memory cache with file-backed storage that eliminates data races by design. |
| `swift-protocol-di-testing` | testing error paths without real I/O, mocking boundaries, designing testable architecture with actors and `Sendable` | Protocol-based dependency injection: abstract file system, network and external APIs behind small focused protocols, inject via default parameters, test with Swift Testing (`@Test`/`@Suite`/`#expect`/`#require`). |

## Related

Skills coordinate with the rest of the setup: the verification-pair hook enforces an ordering between two of them, `walkthrough` is invoked by the response-discipline rule, and `memory-capture` is the review gate for everything the memory hooks stage. See [[Hooks]], [[Rules]], and [[Memory-System]].
