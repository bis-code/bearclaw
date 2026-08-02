#!/bin/sh
# pretooluse-confirm-gate.sh — PreToolUse gate (user scope, all projects).
#
# Denies outward-facing / hard-to-reverse Bash commands unless the WHOLE command
# is prefixed with `CLAUDE_CONFIRMED=1`. Returns permissionDecision "deny", which
# holds even under skip-permission / bypass modes. When confirmed or unrelated,
# emits nothing (exit 0) so the normal deny/allow/ask cascade still applies — it
# never force-allows.
#
# Gated actions: git push, gh pr create, railway, vercel deploy/--prod,
# npm/pnpm/yarn (run) deploy, and raw DROP/TRUNCATE via psql/mysql/mariadb.
# Matching is token-anchored per command segment so
# it does NOT false-deny commands that merely mention a keyword (echo, grep, cat).
# Known limitation: does not parse command substitution / subshells / heredocs —
# the threat model is accidental execution, not adversarial evasion.

# errexit is off by default in sh; every exit below is explicit.

INPUT=$(cat)
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[ "$TOOL" = "Bash" ] || exit 0
[ -n "$CMD" ] || exit 0

# Confirmation is honored ONLY as a leading prefix of the entire command.
case "$CMD" in
    CLAUDE_CONFIRMED=1\ *|CLAUDE_CONFIRMED=1) exit 0 ;;
esac

# Split on && ; | into segments; strip each segment's surrounding whitespace and
# match the gated verb as the segment's command (token-anchored), not a substring.
gated=""
old_ifs=$IFS
segments=$(printf '%s' "$CMD" | sed 's/&&/\n/g; s/;/\n/g; s/|/\n/g')
IFS='
'
for seg in $segments; do
    seg=$(printf '%s' "$seg" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    case "$seg" in
        "git push"|"git push "*)              gated="git push" ;;
        "gh pr create"|"gh pr create "*)      gated="gh pr create" ;;
        "railway"|"railway "*)                gated="railway" ;;
        "vercel deploy"|"vercel deploy "*)    gated="vercel deploy" ;;
        "vercel "*"--prod"*)                  gated="vercel deploy" ;;
        "pnpm deploy"|"pnpm deploy "*|"pnpm run deploy"|"pnpm run deploy "*) gated="deploy script" ;;
        "npm run deploy"|"npm run deploy "*)  gated="deploy script" ;;
        "yarn deploy"|"yarn deploy "*|"yarn run deploy"|"yarn run deploy "*) gated="deploy script" ;;
    esac
    # Raw SQL destruction: only when a DB client is the segment's command AND the
    # segment contains DROP/TRUNCATE (case-insensitive). Anchored so a mention in
    # an unrelated command (echo, grep) does not trip it.
    if [ -z "$gated" ]; then
        case "$seg" in
            psql*|mysql*|mariadb*)
                if printf '%s' "$seg" | grep -qiE '\b(drop|truncate)\b'; then
                    gated="destructive SQL"
                fi ;;
        esac
    fi
    # git --no-verify / -n bypass: match the flag only OUTSIDE quoted strings, so a
    # commit MESSAGE mentioning "--no-verify" (e.g. committing this hook) is not gated.
    if [ -z "$gated" ]; then
        seg_noq=$(printf '%s' "$seg" | sed "s/'[^']*'//g; s/\"[^\"]*\"//g")
        case "$seg_noq" in
            "git "*" --no-verify"*) gated="git --no-verify" ;;
            "git commit -n"|"git commit -n "*|"git commit "*" -n"|"git commit "*" -n "*) gated="git --no-verify" ;;
        esac
    fi
    [ -n "$gated" ] && break
done
IFS=$old_ifs

[ -n "$gated" ] || exit 0

REASON="Outward-facing action '$gated' requires explicit confirmation. Re-run with the command prefixed by CLAUDE_CONFIRMED=1 once you are sure."
jq -n --arg reason "$REASON" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$reason}}'
exit 0
