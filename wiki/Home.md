bearclaw is a complete user-scope [Claude Code](https://claude.com/claude-code) config — 16 subagents, 17 skills, 20 hook scripts, a three-tier memory system that grows as you work, and a safety guard that blocks catastrophic deletes regardless of permission mode.

## The mental model

**The repo is the source of the config.** `install.sh` **copies** the checkout into `~/.claude/`, and records where the copy came from in `~/.claude/.installed-from` (`repo=` and `sha=`). So there are two real trees, and the sha tells you which version is live.

It used to symlink, and the two models differ in ways worth knowing up front:

- **Changes don't propagate on their own.** After a `git pull`, re-run `install.sh`. Under symlinks a pull silently retargeted a running setup — convenient right up to the pull that changed a hook mid-session.
- **Editing `~/.claude/` no longer edits the repo.** Try something live, then port it back deliberately. `bin/claude-setup-doctor` compares the installed sha against the repo and warns when they diverge, which is the check that replaces "they're the same file, so they can't diverge."
- **Nothing can clobber the link, because there isn't one.** Claude Code atomic-writes `settings.json` on `/config`, `/effort`, and plugin changes; that used to replace the symlink with a real file and drop repo-only keys. Now the live file and the repo's canonical one are simply two files, and a SessionStart hook merges the live one's keys back (see [[Hooks]]).

Because the source of the config is a git checkout, every behavioral change is still reviewable as a diff.

**Anti-bloat.** The repo mirrors the live setup, not "what we might want." If a hook, agent, skill, or rule isn't load-bearing for everyday use, it's out — re-add when actually needed. Several components exist because a prose rule demonstrably failed to change behavior and had to be mechanized as a hook; that provenance is recorded in the files themselves rather than trimmed away.

## Pages

| Page | What's in it |
|---|---|
| [[Installation]] | Clone, dry-run, install, doctor; copies vs the symlinks it used to make; what `install.sh` does and provably does not touch; removal; optional dependencies; mirroring to a second config root. |
| [[Hooks]] | The lifecycle events bearclaw wires into, why each of the 19 wired hooks exists, the fail-open philosophy, and the two safety guards. |
| [[Skills]] | The 17-skill catalog grouped by purpose — session continuity, interactive review, maintenance, dev workflow, Swift deep-dives — with trigger phrases and outputs. |
| [[Agents]] | The 16-agent roster, dispatch-routing discipline, and the model-selection rules that keep sub-agent cost honest. |
| [[Memory-System]] | The three tiers, the capture → review-gate → recall loop, `MEMORY.md`/`ERRORS.md` conventions, and the privacy guarantee. |
| [[Rules]] | The `rules/` tier — behavioral instructions loaded every session — file by file, including the incident that produced the background-agent safety rules. |
| [[Testing-and-CI]] | Test-suite layout, the pre-push lanes, the structural identity-leak gate, and the macOS↔Linux portability trap CI exists to catch. |

New here? Read [[Installation]], run the install, then skim [[Hooks]] — the hooks are where most of bearclaw's observable behavior lives.
