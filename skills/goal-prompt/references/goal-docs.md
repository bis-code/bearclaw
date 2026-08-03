# Claude Code `/goal` — condensed official docs

Condensed from https://code.claude.com/docs/en/goal (fetched 2026-08-03).
Re-fetch that URL if this looks stale or behavior differs.

## What it is

`/goal` (Claude Code v2.1.139+) sets a **completion condition** for the current
session. After each turn, a small fast model (the configured Haiku-class model)
checks whether the condition holds against the conversation. If not, Claude
starts another turn instead of returning control. The goal clears automatically
once the condition is met.

Use it for substantial work with a **verifiable end state**: migrate until all
call sites compile and tests pass, implement a design doc until acceptance
criteria hold, drain a labeled issue backlog until empty.

## vs /loop vs Stop hook vs auto mode

| Approach | Next turn starts when | Stops when |
|---|---|---|
| `/goal` | Previous turn finishes | Evaluator model confirms the condition is met |
| `/loop` | A time interval elapses | You stop it, or Claude decides work is done |
| Stop hook | Previous turn finishes | Your own script/prompt decides |

- `/goal` is session-scoped; a Stop hook lives in settings and applies to every
  session in its scope. `/goal` is literally a wrapper around a session-scoped
  prompt-based Stop hook.
- **Auto mode is complementary, not overlapping**: auto mode approves tool calls
  within a turn; `/goal` starts new turns. A goal does NOT change permissions —
  for unattended runs, pair `/goal` with auto mode.

## Usage

- **Set:** `/goal <condition>` — starts a turn immediately with the condition as
  the directive; no separate prompt needed. One goal per session; setting a new
  one replaces the old. A `◎ /goal active` indicator shows runtime.
- **Status:** `/goal` with no argument — shows condition, duration, turns
  evaluated, token spend, and the evaluator's most recent reason.
- **Clear:** `/goal clear` (aliases: `stop`, `off`, `reset`, `none`, `cancel`).
  `/clear` (new conversation) also removes an active goal.
- **Resume:** an active goal is restored by `--resume`/`--continue`; turn count,
  timer, and token baseline reset. Achieved/cleared goals are not restored.
- **Headless:** `claude -p "/goal <condition>"` runs the loop to completion in
  one invocation. Default text output prints nothing until done — add
  `--output-format stream-json --verbose` to watch progress. Ctrl+C interrupts.

## Writing an effective condition

The evaluator **does not run commands or read files** — it judges only what
Claude has surfaced in the conversation. Write the condition as something
Claude's own output can demonstrate ("all tests in `test/auth` pass" works
because the test run lands in the transcript).

A condition that holds up across many turns has:

1. **One measurable end state** — a test result, build exit code, file count,
   empty queue.
2. **A stated check** — how Claude proves it: "`npm test` exits 0",
   "`git status` is clean".
3. **Constraints that matter** — what must NOT change on the way: "no other
   test file is modified".
4. **A bound** — include a turn/time clause like "or stop after 20 turns";
   Claude reports progress against it and the evaluator judges it.

Max 4,000 characters.

## Evaluation mechanics & requirements

- Evaluator = the configured small fast model (default Haiku; override via
  `ANTHROPIC_DEFAULT_HAIKU_MODEL` — warning: that env var affects ALL
  small-fast-model uses, not just /goal). It answers yes/no with a short
  reason; "no" reasons are fed to Claude as guidance for the next turn.
  Evaluation tokens are typically negligible.
- Requires an accepted trust dialog (evaluator is part of the hooks system).
  Unavailable when `disableAllHooks` is set at any level or
  `allowManagedHooksOnly` is set in managed settings — the command says why.
