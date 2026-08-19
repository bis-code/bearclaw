Twenty hook scripts, nineteen wired as Claude Code lifecycle hooks — what each event is for, why each hook exists, and how the two safety guards work.

## The lifecycle model

Claude Code fires hooks at defined points in a session and passes each one a JSON payload on stdin. A hook is **shell the harness runs**, not something Claude decides to call — which is exactly why hooks can enforce things a prose rule cannot, and also why a hook can never invoke a slash command or skill (see the "Hooks can't trigger slash commands" note in [[Rules]]).

Events bearclaw wires into, and what it uses each one for:

| Event | Fires | bearclaw's use |
|---|---|---|
| `SessionStart` | session begins | Surface memory; repair a clobbered `settings.json`. |
| `PreToolUse` | before a tool call, **regardless of permission mode** | Safety guards and steering gates — the only place a decision can be blocked. |
| `UserPromptSubmit` | your prompt is submitted | Inject relevant memory; nudge toward deeper reasoning on design prompts. |
| `Stop` | an assistant turn ends | Context-budget warning, response-shape nudge, cost row, memory index + signal. |
| `SessionEnd` | session ends | Queue a raw memory capture for later review. |
| `PreCompact` | just before compaction discards the conversation | Snapshot git/working state; queue the same raw capture. |
| `PostCompact` | after compaction | Resume the in-flight task (auto-compacts only). |
| `Notification` | Claude wants your attention | Desktop notification, labeled by notification type. |

Two of the twenty scripts serve double duty or none: `sessionend-memory-capture.sh` is wired to **both** `SessionEnd` and `PreCompact`, and `memory-index-freshness.sh` is a shared library called by `install.sh` and `stop-memory-index-rebuild.sh` rather than registered as a hook. That is the 20-scripts / 19-wired arithmetic.

## Fail-open philosophy

Hooks run on the hot path of every session start, every prompt, and every turn end. bearclaw's contributing rules therefore require they be POSIX `sh` (not bash), stay under roughly 50ms, and **fail open** — a broken hook must never block work.

In practice that means:

- `set +e` at the top of most scripts, and explicit `exit 0` on every path.
- Guarded dot-sources: a failed `.` aborts the whole script under `dash` even with `set +e`, which would print a stderr error on every prompt — so each source is `[ -f … ] && . …`.
- The destructive guard wraps its own logic in `try`/except and exits 0 on any internal error: a bug in the guard must not stop legitimate work.
- Advisory hooks emit a `systemMessage` and exit 0 rather than returning a permission decision.

The deliberate exceptions are the gates that *must* be able to say no: the confirm gate, the destructive guard, the dispatch gate, and the verification-pair gate return `permissionDecision: "deny"`. Three of those four are **speed bumps, not walls** — they deny at most once per session, so a false positive costs one extra turn and never locks you out.

Every hook also takes environment seams (`*_DIR`, `*_BIN`, `*_CMD` overrides) so its tests never touch real machine state. Every hook ships a test; see [[Testing-and-CI]].

## The wired hooks

### SessionStart

| Script | Why it exists |
|---|---|
| `sessionstart-load-memory.sh` | The harness only natively loads memory for the current directory's project dir. This surfaces memory regardless of cwd: the global index, the last few global `ERRORS.md` entries, and the current repo's local index. Best-effort — missing files are skipped, and it always exits 0. Honors a slim mode (`memorySlimLoad`) that skips eager dumps because the recall hook serves bodies on demand. |
| `sessionstart-heal-settings.sh` | Claude Code atomic-writes `settings.json` on `/config`, `/effort`, and plugin changes. The temp-file rename replaces the repo **symlink with a real file** and drops repo-only keys (`effortLevel` was observed lost this way). This hook detects the clobber, merges the live file's keys back into the repo's canonical `settings.json` so nothing is lost, and re-asserts the symlink. Idempotent — a no-op when the symlink is intact. |

### PreToolUse

| Matcher | Script | Why it exists |
|---|---|---|
| `Bash` | `pretooluse-confirm-gate.sh` | Outward-facing and hard-to-reverse commands should not happen by accident. See below. |
| `Bash` | `pretooluse-secret-guard.sh` | Advisory only, never blocks. Warns when a command would dump secret-bearing file contents (`*.env*`, `*credentials*.json`, `*token*.json`, `*secret*`) or a raw key-like literal into the transcript. The rationale is precise: the risk isn't the read, it's that **the transcript is persisted permanently**. It nudges toward `jq -r 'keys'` or redaction. |
| `Bash` | `guard-destructive.py` | Blocks catastrophic deletes regardless of permission mode. See below. |
| `Edit\|Write\|MultiEdit` | `pretooluse-config-protection.sh` | Asks for confirmation before modifying an **existing** lint/format config, to block the "weaken the linter to silence the error" failure mode. Covers ESLint, Biome, Prettier, golangci-lint, markdownlint, commitlint, SwiftLint, Ruff, flake8, RuboCop. New configs pass freely so bootstrapping is unaffected. |
| `Task\|Agent` | `pretooluse-dispatch-gate.sh` | Mechanizes the dispatch cheat sheet: when a general-purpose dispatch's prompt clearly matches a named agent's trigger, deny once and name the agent. The evidence for building it: an audit found 73% of 2,443 dispatches were general-purpose despite the prose rule, and a prose-only fix the month before moved nothing. A secondary advisory fires once per session when `model:` is omitted from a dispatch (silent tier inflation). Also denies a background dispatch that lacks worktree isolation. |
| `Skill` | `pretooluse-verification-pair.sh` | Enforces a required pair: `verification-before-completion` must run before `finishing-a-development-branch`. Evidence: an audit found 2 verification runs against 10 finishing runs — a 20% rate, unchanged from the prior month despite the prose rule. Records the verification in a per-session marker; denies an unpaired finish once, then lets it through. |

### UserPromptSubmit

| Script | Why it exists |
|---|---|
| `userpromptsubmit-deepthink-nudge.sh` | Thirty days of transcripts showed **zero** deep-think calls despite a prose mandate: rules don't steer tool choice at decision time, prompt-time context injection does. When the prompt matches an architecture/design trigger (architect, schema design/change/migration, data model, system design, API contract, auth flow, payment flow, multi-module), it injects a reminder to call the think tool first. Fires at most once per session. Stays silent when the plugin isn't installed — nudging toward a tool that cannot start would be a false claim. |
| `userpromptsubmit-memory-recall.sh` | Serves relevant memory on demand instead of dumping everything at session start. Skips trivial prompts (fewer than four words, `y`/`yes`/`no`/`ok`/`continue`, slash commands), searches both the global and repo-local indexes, merges, and passes the hits through a formatter with a relevance floor, a top-k of 3 and a 400-token budget. Surfaced entry ids are appended to a usage log that feeds frequency/recency scoring on later turns. Resolves the **main** worktree so every linked worktree shares one repo index. |

### Stop

| Script | Why it exists |
|---|---|
| `stop-handoff-reminder.sh` | Warns via `systemMessage` once the transcript passes a configurable percentage of the effective `autoCompactWindow`, so you still have headroom to run `/handoff` before auto-compact strips the conversation. The threshold is **computed from settings, never hardcoded**, so it stays correct when you change the window; it measures the exact context size from API usage rather than guessing from bytes. Re-warns only after another band of growth. Always exits 0. |
| `stop-askquestion-nudge.sh` | Enforces "ask via selectable options, not prose": when a turn ends with a discrete 2–4 way choice written as a prose list instead of an `AskUserQuestion` call, it blocks **once per session** and asks for a re-ask via the tool. Hooks can't force a tool call, so this only catches lapses; detection deliberately requires an explicit options shape to keep false nags rare, and it stands down when the current Stop is itself the result of a previous block (loop safety). |
| `cost-tracker.sh` | Appends one per-turn **delta** cost row to a local metrics file, backing `/cost-report`. Non-blocking by design: the transcript parse and write run in a detached background worker so the hook adds roughly zero latency. Because the Stop payload carries no usage data, the worker sums token usage from the session transcript. Delta rows make today / by-project / last-7d a plain sum plus date filter. A detached worker can't talk back to the current turn, so on write failure it drops an error marker that the next turn surfaces and clears — persistent failures re-nag, transient ones show once. |
| `stop-memory-index-rebuild.sh` | Rebuilds the semantic memory index when a memory file changed since the last build. Freshness is mtime-gated, so this is cheap when nothing changed; the rebuild runs in the background. |
| `stop-memory-signal.sh` | A heuristic, **no-LLM** high-signal-turn detector: regexes the last user and assistant exchange and drops a marker into a per-session signal file, which the `memory-capture` skill later uses to prioritize what to distill. Cheap between-prompt awareness without between-prompt LLM cost. It filters out tool results recorded with `role=="user"` — that's the harness talking, not you, and the filter is load-bearing: CLI stderr was previously being banked as a user correction. |

### SessionEnd, PreCompact, PostCompact, Notification

| Event | Script | Why it exists |
|---|---|---|
| `SessionEnd` | `sessionend-memory-capture.sh` | Writes a **raw capture pointer**, not distilled memory, so sessions that end without a `/handoff` still get reviewed later. No LLM call happens here — a shell hook can't make one. The next session's SessionStart nudges, and the `memory-capture` skill drains the queue. Resolves the main-worktree basename as the project name. |
| `PreCompact` | `precompact-snapshot.sh` | Hooks cannot invoke `/handoff`, so this captures a working-memory snapshot to `~/.claude/handoffs/precompact-<timestamp>.md` right before compaction discards the conversation: git context (repo, branch, working tree, recent commits), the current todo list, recently-edited files, and a tail of the transcript. Read by a future session to recover where the previous one left off. |
| `PreCompact` | `sessionend-memory-capture.sh` | The same raw-capture pointer as the SessionEnd case, so compaction doesn't lose it either. |
| `PostCompact` | `postcompact-resume.sh` | Injects an instruction to read the compact summary, identify the in-flight task, and continue without asking what to do next — pointing at the precompact snapshot for git state when one exists. Fires for **auto**-compacts only: a manual `/compact` is your choice and you'll drive the next turn yourself, so steamrolling it with an auto-resume directive would be wrong. |
| `Notification` | `notify-attention.sh` | Fires a desktop notification only when Claude genuinely needs you, and labels which kind. The `notification_type` discriminator drives the branch: `idle_prompt` (turn ended, truly waiting), `permission_prompt` (a tool or agent wants to proceed), `auth_success` and `elicitation_*` stay silent, and an unknown type fires a generic notification rather than dropping a real one. The old behavior pinged "needs your input" even for agent-dispatch permission prompts that weren't waiting on anyone. Notification text is passed via argv, never string-interpolated, so quotes and backticks can't inject. |

## Safety guard: guard-destructive.py

The one hook that is a wall, not a speed bump. It blocks broad destructive shell commands **even under `--dangerously-skip-permissions`**, because `PreToolUse` hooks run regardless of permission mode. Its header names the root cause it addresses: a background agent running with bypassed permissions wiped a projects root (the incident is described in [[Rules]]).

**It is a parser, not a regex list.** The command is split into segments on *unquoted* separators (`;`, newline, `|`, `&`, with `&&`/`||` collapsed), and a segment is inspected only when its real command word is destructive — `rm`, `git`, `find`, `chmod`, `chown` — after skipping wrappers like `sudo`, `env`, `nohup`, `xargs` and leading `VAR=value` assignments. So `echo "rm -rf ~/foo"`, comments, and documentation are **not** flagged; only an actual invocation is.

What gets denied:

| Command | Blocked when |
|---|---|
| `rm` (recursive **and** force) | Target is `/`, `/*`, `~`, `~/`, `$HOME`, `${HOME}`, `..`, `../*`, `*`, or `./*` |
| | Target is a bare variable like `$FOO` or `${FOO}/*` — an empty expansion could hit `$HOME` or `/` |
| | Target is a system path: `/etc`, `/var`, `/usr`, `/bin`, `/sbin`, `/System`, `/Library`, `/opt`, `/private` |
| | Target is a **shallow home path** — 2 or fewer levels under `~`, e.g. `~/foo` or `~/foo/bar`. The denial message tells you the way through: run it from inside the project with a relative path, or name a deeper subdirectory. |
| | Target begins with a top-level glob, e.g. `/var*` |
| `git clean` | `-f`, `-d` and `-x` are all present — it removes all untracked *and* ignored files. Suggests verifying the repo root or using `git stash -u`. |
| `find` | `-delete` or `-exec … rm` with the search root at `/` or under a home root. |
| `chmod` / `chown` | Recursive, targeting `/`, `~`, `$HOME`, or one level under home. Every non-flag token is checked, not just the first — the mode (`777`) or owner spec (`user:group`) precedes the path, so stopping at the first candidate would inspect the mode and never reach the target. |
| any | A `>` redirect-truncation over a home dotfile (matches outside quotes; `>>` and `2>` are excluded). Suggests editing the file instead. |
| any | The classic fork-bomb pattern. |

Narrow project-local deletes stay allowed — `rm -rf node_modules`, `rm -rf dist` from inside a project are exactly what the shallow-path rule is designed *not* to catch. Portability is deliberate too: the home root (`/Users` on macOS, `/home` on Linux) is derived at runtime rather than hardcoded. Behavior is pinned by `scripts/tests/guard-destructive.bats`.

## Safety guard: pretooluse-confirm-gate.sh

Denies outward-facing or hard-to-reverse Bash commands unless the **whole command** is prefixed with `CLAUDE_CONFIRMED=1`. The denial message tells you what to do:

> Outward-facing action '<action>' requires explicit confirmation. Re-run with the command prefixed by CLAUDE_CONFIRMED=1 once you are sure.

Gated actions: `git push`, `gh pr create`, `railway`, `vercel deploy` (and any `vercel … --prod`), `npm`/`pnpm`/`yarn` deploy scripts, raw `DROP`/`TRUNCATE` through `psql`/`mysql`/`mariadb`, and `git … --no-verify` / `git commit -n`.

Three design details matter:

- **It returns `deny`**, which holds even under skip-permission and bypass modes.
- **It never force-allows.** When the command is confirmed or unrelated it emits nothing and exits 0, so the normal deny/allow/ask cascade still applies.
- **Matching is token-anchored per command segment**, so a command that merely *mentions* a keyword (`echo`, `grep`, `cat`) is not falsely denied. The `--no-verify` check strips quoted strings first, so a commit *message* mentioning `--no-verify` doesn't trip the gate.

Stated limitation, from the script's own header: it does not parse command substitution, subshells, or heredocs. The threat model is **accidental execution, not adversarial evasion** — an agent that wants to evade this gate can, and that is an accepted boundary.

## Adding a hook

Three requirements from `CONTRIBUTING.md`: it ships a test at `hooks/<name>.test.sh` exercising it through env seams (a non-shell hook gets a `.bats` file in `scripts/tests/` instead); it is POSIX `sh`, fast, and fails open; and it must be load-bearing for everyday use — explain in the PR why you need it, not why it might be nice. Then wire it into `settings.json` under the right event with a `timeout`.
