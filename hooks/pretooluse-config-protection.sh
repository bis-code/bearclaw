#!/bin/sh
# pretooluse-config-protection.sh — PreToolUse gate (Edit|Write|MultiEdit).
# Asks for confirmation before modifying an EXISTING lint/format/quality config,
# to block the "weaken the linter to silence the error" failure mode. New configs
# (file does not yet exist) pass freely so bootstrapping is unaffected.

INPUT=$(cat)
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

case "$TOOL" in Edit|Write|MultiEdit) ;; *) exit 0 ;; esac
[ -n "$FILE" ] || exit 0

base=$(basename "$FILE")
protected=0
case "$base" in
    .eslintrc|.eslintrc.*|eslint.config.*|biome.json|biome.jsonc \
    |.prettierrc|.prettierrc.*|prettier.config.* \
    |.golangci.yml|.golangci.yaml|.markdownlint.json \
    |commitlint.config.*|.swiftlint.yml|.swiftlint.yaml \
    |ruff.toml|.flake8|.rubocop.yml) protected=1 ;;
esac
[ "$protected" -eq 1 ] || exit 0
# Guard EXISTING files only — creating a new config is fine.
[ -f "$FILE" ] || exit 0

REASON="Editing existing lint/format config '$base'. Confirm this is an intended change, not weakening the linter to silence an error — fix the code instead when possible."
jq -n --arg reason "$REASON" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:$reason}}'
exit 0
