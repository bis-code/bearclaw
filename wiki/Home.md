bearclaw is a complete user-scope [Claude Code](https://claude.com/claude-code) config — 16 subagents, 17 skills, 20 hook scripts, a three-tier memory system that grows as you work, and a safety guard that blocks catastrophic deletes regardless of permission mode.

## The mental model

**The repo *is* the config.** `install.sh` symlinks the checkout into `~/.claude/`, so `~/.claude/settings.json` and `<repo>/settings.json` are the same file. Editing the live config edits the repo; your changes stay version controlled by construction, with no export step and no copy to drift out of sync. You commit that drift yourself — `bin/claude-setup-doctor` warns when the tree is dirty.

That symlink choice has consequences worth knowing up front. Claude Code atomic-writes `settings.json` on `/config`, `/effort`, and plugin changes, which replaces the symlink with a real file; a SessionStart hook detects that and heals it (see [[Hooks]]). And because the live config is a git checkout, every behavioral change is reviewable as a diff.

**Anti-bloat.** The repo mirrors the live setup, not "what we might want." If a hook, agent, skill, or rule isn't load-bearing for everyday use, it's out — re-add when actually needed. Several components exist because a prose rule demonstrably failed to change behavior and had to be mechanized as a hook; that provenance is recorded in the files themselves rather than trimmed away.

## Pages

| Page | What's in it |
|---|---|
| [[Installation]] | Clone, dry-run, install, doctor; what `install.sh` does and provably does not touch; uninstall; optional dependencies; mirroring to a second config root. |
| [[Hooks]] | The lifecycle events bearclaw wires into, why each of the 19 wired hooks exists, the fail-open philosophy, and the two safety guards. |
| [[Skills]] | The 17-skill catalog grouped by purpose — session continuity, interactive review, maintenance, dev workflow, Swift deep-dives — with trigger phrases and outputs. |
| [[Agents]] | The 16-agent roster, dispatch-routing discipline, and the model-selection rules that keep sub-agent cost honest. |
| [[Memory-System]] | The three tiers, the capture → review-gate → recall loop, `MEMORY.md`/`ERRORS.md` conventions, and the privacy guarantee. |
| [[Rules]] | The `rules/` tier — behavioral instructions loaded every session — file by file, including the incident that produced the background-agent safety rules. |
| [[Testing-and-CI]] | Test-suite layout, the pre-push lanes, the structural identity-leak gate, and the macOS↔Linux portability trap CI exists to catch. |

New here? Read [[Installation]], run the install, then skim [[Hooks]] — the hooks are where most of bearclaw's observable behavior lives.
