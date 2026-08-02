---
name: context-budget
description: Use to audit Claude Code context-window overhead — estimated token consumption across agents, skills, MCP servers, rules, and CLAUDE.md — and get prioritized token-savings recommendations. Triggers include "context budget", "what's eating my context", "do I have room to add X", "/context-budget", or sessions feeling sluggish after adding components. On-demand and read-only.
---

# Context Budget

Estimate token overhead across every loaded component in the active Claude Code config root and surface actionable optimizations to reclaim context space.

**Announce at start:** "I'm using the context-budget skill to audit context overhead."

**Read-only.** This skill measures and recommends; it never removes components. Apply removals yourself (or via the relevant cleanup).

**Scope:** scan the active config root — `${CLAUDE_CONFIG_DIR:-$HOME/.claude}` for `agents/`, `skills/`, `rules/` — plus the project + user `CLAUDE.md` chain and the active `.mcp.json`. Many of these are symlinks (e.g. `~/.claude/skills` → claude-setup, and `~/.claude-work` mirrors it): **resolve symlinks and skip identical copies** so a component shared across config roots is counted once.

## How It Works

### Phase 1: Inventory

Estimate tokens per component (`words × 1.3` for prose, `chars / 4` for code-heavy files):

- **Agents** (`agents/*.md`) — flag files >200 lines (heavy on every Task spawn), `description` >30 words (loaded always).
- **Skills** (`skills/*/SKILL.md`) — flag files >400 lines; skip symlinked/duplicate copies.
- **Rules** (`rules/**/*.md`) — flag files >100 lines; detect overlapping content between rule files. (Note: `rules/` is loaded **every session** — it's the highest-leverage bucket here.)
- **MCP servers** (`.mcp.json` / active config) — count servers + tools; estimate ~500 tokens/tool schema; flag servers with >20 tools or that merely wrap a CLI (`gh`, `git`, `npm`, `vercel`).
- **CLAUDE.md** (project + user) — flag combined >300 lines.

### Phase 2: Classify

| Bucket | Criteria | Action |
|--------|----------|--------|
| **Always needed** | Referenced in CLAUDE.md/rules, backs an active command, matches current project | Keep |
| **Sometimes needed** | Domain-specific, not referenced (e.g. a language reviewer) | Fine as-is — agents/skills are on-demand (description-only idle cost) |
| **Rarely needed** | No reference, overlapping content, no project match | Remove or lazy-load |

> In this setup agents + skills are **on-demand** (only their `description` is always-loaded), so the biggest always-loaded levers are **`rules/`**, **`CLAUDE.md`**, and **MCP tool schemas** — focus there.

### Phase 3: Detect Issues

- **Bloated agent/skill descriptions** (>30 words) — loaded into every Task/skill-selection context.
- **Heavy agents** (>200 lines) — inflate Task context on every spawn.
- **Redundant components** — skills duplicating agent logic, rules duplicating CLAUDE.md.
- **MCP over-subscription** — many servers, or servers wrapping free CLIs.
- **CLAUDE.md / rules bloat** — verbose explanations, outdated sections, instructions that should be one-line.

### Phase 4: Report

```
Context Budget Report
═══════════════════════════════════════
Total estimated always-loaded overhead: ~XX,XXX tokens
Window: ~200K (Sonnet) / check current model

Component         Count   ~Tokens
Agents (descs)    N       ~X,XXX
Skills (descs)    N       ~X,XXX
Rules             N       ~X,XXX   (always-loaded)
MCP tool schemas  N       ~XX,XXX
CLAUDE.md         N       ~X,XXX

Top optimizations (ranked by tokens saved):
1. <action> → ~X,XXX
2. <action> → ~X,XXX
3. <action> → ~X,XXX
```

Verbose mode: per-file token counts, the heaviest files line-by-line, overlapping rule lines side by side, and the MCP tool list with per-tool schema estimates.

## Best Practices

- **MCP is usually the biggest lever**: each tool schema ~500 tokens; a 30-tool server can outweigh all skills combined.
- **`rules/` is the always-loaded tax** here (agents/skills are on-demand): scrutinize it first.
- **Descriptions load even when the component never runs** — keep agent/skill `description` fields tight.
- **Audit after adding** any agent, skill, or MCP server to catch creep early.

## Related

- **`monthly-setup-audit`** — broad, periodic (monthly) read-only health-check of the whole setup; context-budget is the *focused, on-demand token* slice of that. Run this mid-session ("do I have room?"); run monthly-setup-audit on a cadence.
- **`/cost-report`** — tracks **dollar** spend (cost-tracker metrics), not context tokens. Complementary: this skill = context headroom, cost-report = money.
