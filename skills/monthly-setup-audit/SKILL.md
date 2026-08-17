---
name: monthly-setup-audit
description: Use when the user asks to audit, review, health-check, or "spring-clean" the Claude Code setup/config — or asks "what's eating my context" / for a context budget — runs a read-only tiered fan-out over agents, skills, rules, context overhead, conversations, memory, and per-repo .claude dirs, then produces a dated risk-grouped report and applies only the safe fixes on confirmation. Intended to run roughly monthly.
context: fork
allowed-tools: Read, Glob, Grep, Bash
---

# Monthly Setup Audit

**Announce at start:** "I'm using the monthly-setup-audit skill to run the setup health-check."

## What it does

A three-phase, READ-ONLY audit:
1. **Collect** — `scripts/audit-collect.sh` gathers deterministic evidence (config inventory, friction signatures, memory integrity, cost/drift) into a temp dir. Near-zero token cost.
2. **Analyze + Synthesize** — a `Workflow` fans out 4 lane agents over the evidence, then one opus synthesizer writes a risk-grouped report.
3. **Apply (gated)** — only after the user confirms, and only the **safe/reversible** fixes.

## Steps

1. Resolve paths (run in Bash):

   ```bash
   # Resolve the repo from the live install — clone paths differ per machine
   # (clone paths differ per machine).
   SETUP_REPO="$(dirname "$(readlink -f "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/CLAUDE.md")")"
   MONTH="$(date +%Y-%m)"
   REPORT="$SETUP_REPO/docs/audits/${MONTH}-claude-setup-audit.md"
   PREV="$(ls -1 "$SETUP_REPO"/docs/audits/*-claude-setup-audit.md 2>/dev/null | grep -v "$MONTH" | tail -1)"
   EVID="$(bash "$SETUP_REPO/scripts/audit-collect.sh" | tail -1)"
   echo "evidence=$EVID report=$REPORT prev=${PREV:-none}"
   ```

2. Launch the Workflow over the collected evidence:

   ```
   Workflow({
     scriptPath: "<SETUP_REPO>/skills/monthly-setup-audit/audit-workflow.js",
     args: { evidenceDir: "<EVID>", reportPath: "<REPORT>", prevReportPath: "<PREV or empty>" }
   })
   ```

   (Substitute the real values from step 1. This skill authorizes the Workflow call.)

3. When it completes, read `<REPORT>` and present to the user:
   - the Summary,
   - the **Safe / reversible** fix list (these are apply-eligible),
   - a one-line count of Destructive and Work-scope items (review-only).

4. **Gate — ask before changing anything.** Ask: "Apply the safe/reversible fixes now?"
   - On yes: apply ONLY the safe items, one at a time, showing each command before running it.
   - **NEVER** touch anything under `~/work` (surface only).
   - **NEVER** `git add -A`; stage specific files. **NEVER** auto-commit unless the user explicitly says to.
   - Destructive items: list them, do not execute — the user handles those manually.

5. Offer to commit the report:

   ```bash
   git -C "$SETUP_REPO" add "docs/audits/${MONTH}-claude-setup-audit.md"
   git -C "$SETUP_REPO" commit -m "docs(audit): ${MONTH} setup health-check

   Generated with Claude Code
   Co-Authored-By: Claude <noreply@anthropic.com>"
   ```

## Guardrails

- The fan-out is strictly read-only; collectors only read.

## Context-budget lane

<!-- Folded from the context-budget skill 2026-08-16 (S7). Also serves the
on-demand "do I have room?" ask — run just this lane then. -->

Estimate always-loaded token overhead (`words x 1.3` prose, `chars/4` code),
resolving symlinks and counting shared components once:
- **rules/** (loaded EVERY session — the highest-leverage bucket) + **CLAUDE.md** chain: flag verbose/overlapping content; combined ceiling enforced by scripts/test-all.sh's size guard.
- **Agent/skill descriptions** (always-loaded even when never run): flag >30 words.
- **Agents >200 lines / skills >400 lines**: heavy per-spawn cost.
- **MCP tool schemas** (~500 tok/tool): flag servers >20 tools or wrapping free CLIs; read BOTH `.mcp.json` and `~/.claude.json` mcpServers.
Report per-bucket totals + top optimizations ranked by tokens saved.
- Cost: 5 agents reading bounded evidence (~150–300k tokens), not raw transcripts.
- If a lane returns no data, the report flags it under Coverage gaps — never silently dropped.
- Cadence is manual. There is no auto-cron; the user triggers this.
- Memory findings are detect-only here; run `scripts/memory-doctor.sh --apply <memory-dir>` to fix index drift (per-tier: `~/.claude/memory-global` and a repo's `.claude/memory`).
