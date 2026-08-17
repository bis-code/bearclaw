#!/bin/sh
# pretooluse-secret-guard.sh — PreToolUse advisory (Bash). NEVER blocks (exit 0).
# Warns when a command would dump secret-bearing file contents to the transcript
# (*.env*, *credentials*.json, *token*.json, *secret*) or contains a raw key-like
# literal (0x + 40+ hex, or a bare 64-hex string). Emits a systemMessage nudging
# toward `jq -r 'keys'` / redaction. Rationale: keys here are test keys; the real
# risk is the persisted transcript, not the read itself. Advisory by design.

INPUT=$(cat)
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[ "$TOOL" = "Bash" ] || exit 0
[ -n "$CMD" ] || exit 0

warn=""
# A secret-bearing file path appears in the command.
# The 'secret' arm requires a path-ish shape (extension or trailing slash) —
# the bare-word match flagged any command merely CONTAINING "secret"
# (e.g. `git log --grep secret`), drowning the signal (tightened 2026-08-16).
if printf '%s' "$CMD" | grep -qiE '(\.env([.][a-z0-9_]+)?|credentials[^[:space:]]*\.json|token[^[:space:]]*\.json|[a-z0-9_.-]*secrets?[a-z0-9_.-]*(\.[a-z0-9]+|/))'; then
    warn="references a secrets-bearing file"
fi
# A raw key-like literal appears in the command text.
if [ -z "$warn" ] && printf '%s' "$CMD" | grep -qE '(0x[0-9a-fA-F]{40,}|[0-9a-fA-F]{64})'; then
    warn="contains a raw key-like literal"
fi

[ -n "$warn" ] || exit 0

MSG="Heads-up: this command $warn — output is saved in the transcript permanently. If the value is sensitive, prefer 'jq -r \"keys\"' or redaction over printing it. (Advisory; not blocked.)"
jq -n --arg m "$MSG" '{systemMessage:$m}'
exit 0
