#!/bin/sh
# pretooluse-dispatch-gate.sh — PreToolUse (Task|Agent) dispatch steering.
# Mechanizes the CLAUDE.md dispatch cheat sheet: when a general-purpose (or
# unset/claude) dispatch's prompt+description clearly matches a cheat-sheet
# trigger, DENY once with the named agent. SPEED BUMP, NOT A WALL: each
# suggested agent denies at most once per session — re-issuing the same call
# passes (informed choice, no lockout). Evidence: June 2026 audit — 73% of
# 2,443 dispatches were general-purpose despite the prose rule; May's prose
# fix moved nothing. Secondary advisory (once/session, never denies): missing
# `model:` on a dispatch (model-selection.md meta-rule 1).
# Env seams (tests): CLAUDE_DISPATCH_STATE_DIR.

INPUT=$(cat)
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
case "$TOOL" in Task|Agent) ;; *) exit 0 ;; esac

SID=$(printf '%s' "$INPUT" | jq -r '.session_id // "nosession"' 2>/dev/null)
SUB=$(printf '%s' "$INPUT" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null)
MODEL=$(printf '%s' "$INPUT" | jq -r '.tool_input.model // empty' 2>/dev/null)
TEXT=$(printf '%s' "$INPUT" | jq -r '((.tool_input.prompt // "") + " " + (.tool_input.description // ""))' 2>/dev/null)

STATE_DIR="${CLAUDE_DISPATCH_STATE_DIR:-${TMPDIR:-/tmp}}"

# --- Secondary advisory: model omitted (silent tier inflation). Once/session.
MODEL_NOTE=""
if [ -z "$MODEL" ]; then
  MMARK="$STATE_DIR/claude-dispatch-modelnudge-$SID"
  if [ ! -f "$MMARK" ]; then
    : > "$MMARK" 2>/dev/null || true
    MODEL_NOTE="REMINDER (rules/model-selection.md): set model: explicitly on every Agent call — haiku=explore/enumerate, sonnet=execute, opus=reason/design. Omitting it inherits the spawner tier (silent cost inflation)."
  fi
fi

# --- Safety gate: background/autonomous dispatch without worktree isolation.
# Root cause of the 2026-06-08 projects-tree wipe was a background agent running with
# bgIsolation:none directly on the live tree. Make worktree isolation the default
# EXPECTATION for background dispatches: deny once/session; re-issue to override
# (read-only agents, or accepted risk). See rules/enforced-guards.md.
BG=$(printf '%s' "$INPUT" | jq -r '.tool_input.run_in_background // false' 2>/dev/null)
ISO=$(printf '%s' "$INPUT" | jq -r '.tool_input.isolation // empty' 2>/dev/null)
if [ "$BG" = "true" ] && [ "$ISO" != "worktree" ]; then
  IMARK="$STATE_DIR/claude-dispatch-isolation-$SID"
  if [ ! -f "$IMARK" ]; then
    : > "$IMARK" 2>/dev/null || true
    jq -n --arg extra "$MODEL_NOTE" \
      '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:("Background dispatch without worktree isolation. Add isolation:\"worktree\" so a runaway agent works on a throwaway copy, never your live tree — bgIsolation:none on a live projects tree caused the 2026-06-08 wipe. If this agent is read-only or you accept the risk, re-issue the same call (denied once per session)." + (if $extra != "" then " " + $extra else "" end))}}'
    exit 0
  fi
fi

# --- Primary gate: general-purpose dispatch vs cheat-sheet triggers.
case "$SUB" in
  ""|general-purpose|claude) GP=1 ;;
  *) GP=0 ;;
esac

# Two suggestion kinds since the S6 roster consolidation (2026-08-16):
#   match  -> a NAMED AGENT still on the roster (dispatch it instead)
#   alt    -> a SKILL / NATIVE FLOW that replaced a retired agent
match=""; alt=""; altkey=""
if [ "$GP" -eq 1 ] && [ -n "$TEXT" ]; then
  m(){ printf '%s' "$TEXT" | grep -qiE "$1"; }
  if   m 'build (fail|error|broke)|compile error|ci (fail|red|broke)|lint (fail|error)'; then match=build-error-resolver
  elif m 'runtime (bug|error)|flaky test|race condition|behaves wrong|unexpected (500|behavior)'; then match=incident-debugger
  elif m 'security (review|audit)|owasp|vulnerab'; then alt="the /security-review skill (security-reviewer agent retired 2026-08-16)"; altkey=securityreview
  elif m 'n\+1|unbounded quer|performance (review|regress)'; then match=performance-reviewer
  elif m 'architecture review|module boundar|coupling'; then match=architect-reviewer
  elif m '(golang|\bgo\b|java|python|c#|csharp|\.net|typescript|javascript|swift) (code )?review|review .*\.(go|java|py|cs|tsx?|swift)\b'; then match=language-reviewer
  elif m 'dead code|duplicated? (logic|code)|unused (import|export)|obsolete scaffold'; then alt="the refactor-clean skill (refactor-cleaner agent retired 2026-08-16)"; altkey=refactorclean
  elif m '\btdd\b|test-?first|failing test first'; then alt="the superpowers:test-driven-development skill (tdd-guide agent retired 2026-08-16)"; altkey=tddskill
  elif m 'update (the )?(readme|changelog|openapi)|sync (the )?docs'; then alt="in-session doc edits (doc-updater agent retired 2026-08-16 — small doc syncs need no subagent)"; altkey=docsync
  elif m 'implementation plan|plan (the |a |this )(feature|implementation|change)|map (the )?affected (code|files)'; then alt="native plan mode or the Plan agent (planner agent retired 2026-08-16)"; altkey=planmode
  # plugin + built-in roster (added 2026-06-18) — kept in sync with CLAUDE.md ### Dispatch routing
  elif m 'create (an? |a new )?(agent|subagent)|author (an? |a new )?agent'; then match=plugin-dev:agent-creator
  elif m 'validate (the |my )?plugin|check plugin (structure|json|manifest)'; then match=plugin-dev:plugin-validator
  elif m 'review (my |the )?skill|skill (quality|description) review|improve (my |the )?skill'; then match=plugin-dev:skill-reviewer
  elif m 'claude code (feature|hook|setting|command|mcp|question|cli)|claude agent sdk|anthropic api|claude api'; then match=claude-code-guide
  elif m 'trace (the |how )|how does .* work|understand how .* (work|behave)|map the (architecture|execution)'; then match=feature-dev:code-explorer
  elif m 'review (the |this |my )?(diff|changes?|pr|code)'; then alt="the /code-review skill (code-reviewer agent retired 2026-08-16)"; altkey=codereview
  elif m 'explore the codebase|search across|find (where|all|every|the file|every (place|usage|reference))|locate (the|where|every)|survey (the|all)'; then match=Explore
  fi
fi

if [ -n "$match" ]; then
  SAFEMATCH=$(printf '%s' "$match" | tr ':/' '__')
  SEEN="$STATE_DIR/claude-dispatch-seen-$SID-$SAFEMATCH"
  if [ ! -f "$SEEN" ]; then
    : > "$SEEN" 2>/dev/null || true
    jq -n --arg a "$match" --arg extra "$MODEL_NOTE" \
      '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:("This task matches the dispatch cheat sheet for `" + $a + "` — dispatch that named agent (subagent_type: \"" + $a + "\") instead of general-purpose. If it genuinely does not fit, re-issue this same call: this gate denies each suggestion only once per session." + (if $extra != "" then " " + $extra else "" end))}}'
    exit 0
  fi
elif [ -n "$alt" ]; then
  SEEN="$STATE_DIR/claude-dispatch-seen-$SID-$altkey"
  if [ ! -f "$SEEN" ]; then
    : > "$SEEN" 2>/dev/null || true
    jq -n --arg a "$alt" --arg extra "$MODEL_NOTE" \
      '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:("This task is covered by " + $a + " — use that instead of a general-purpose agent dispatch. If it genuinely does not fit, re-issue this same call: this gate denies each suggestion only once per session." + (if $extra != "" then " " + $extra else "" end))}}'
    exit 0
  fi
fi

# Allow path — surface the model advisory if pending.
if [ -n "$MODEL_NOTE" ]; then
  jq -n --arg m "$MODEL_NOTE" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"allow",additionalContext:$m}}'
fi
exit 0
