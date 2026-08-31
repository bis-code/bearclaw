#!/bin/sh
# hooks/lib/episodic-recall.sh — transcript history as a recall tier (SOURCED).
#
# The episodic-memory plugin indexes every past Claude Code conversation (1,544
# of them here) and exposes them through an MCP tool. An MCP tool is PULL-only:
# it answers when the model thinks to ask, and the model mostly does not think to
# ask. So the archive sat unused while the same questions got re-derived.
#
# WHEN THIS FIRES — a ruling that departs from the plan, with the measurement.
# The plan said to search history "when curated recall finds nothing strong".
# Measured across the 40-pair eval suite: curated recall injected something on
# 40 of 40 prompts, including all five that should have returned nothing. A
# score-based trigger would therefore have fired zero times — dead code — and on
# the rare prompt where it did fire it would fire on exactly the off-domain
# questions where silence is the right answer, filling them with transcript
# noise instead.
#
# So the trigger is INTENT, not score: it fires when the prompt is asking about
# what happened before ("did we ever", "last time", "what did we decide"), which
# is precisely when the archive is the right source and curated memory is not.
# On every other prompt it does not run at all, so it costs nothing — the CLI
# takes ~0.6s, which the hot path cannot afford on every turn.
#
# Everything here fails open: no plugin, no match, a timeout, an unparseable
# answer — all yield an empty string and the prompt proceeds untouched.

# Deliberately narrow. "before" and "earlier" alone are far too common in
# ordinary requests ("before you commit, run the tests"), so each pattern pairs a
# time reference with a first-person-plural subject or an explicit recall verb.
EPISODIC_INTENT_RE='(did|have) (we|i) (ever|already|previously)|what did (we|i) (decide|do|try|say|use|call|pick|choose)|how did (we|i)|when did (we|i)|last time|previous(ly)? (session|conversation|chat|run)|in (a|an|the) (previous|earlier|past|prior) (session|conversation|chat|run)|remember when|do you remember|we (already )?(tried|decided|discussed|agreed|settled)|have i (ever|already)'

episodic_history_intent() { # $1 = prompt; 0 = asking about history
  printf '%s' "${1:-}" | tr 'A-Z' 'a-z' | grep -Eq "$EPISODIC_INTENT_RE"
}

# Newest installed CLI. Globbed rather than pinned: the plugin is version-pathed
# under plugins/cache and bumps on its own. The copy under plugins/marketplaces
# is NOT usable — it ships without node_modules, so it dies on a missing
# better-sqlite3; only the cache copy has its dependencies.
episodic_cli() {
  _ec_best=""
  for _ec in "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/*/episodic-memory/*/cli/episodic-memory; do
    [ -x "$_ec" ] || continue
    _ec_best="$_ec"   # glob is sorted, so the last match is the newest version
  done
  [ -n "$_ec_best" ] || return 1
  printf '%s\n' "$_ec_best"
}

# Run the CLI under a wall-clock cap. macOS ships no timeout(1) and none of
# coreutils' variants are guaranteed, so this is a plain background watchdog: a
# hook that hangs blocks the user's prompt, which is worse than no history.
_episodic_run() { # $1 = cli, $2 = query, $3 = limit, $4 = deadline (tenths)
  _er_out=$(mktemp 2>/dev/null) || return 1
  "$1" search --limit "$3" "$2" >"$_er_out" 2>/dev/null &
  _er_pid=$!
  _er_i=0
  while kill -0 "$_er_pid" 2>/dev/null; do
    if [ "$_er_i" -ge "$4" ]; then
      kill -TERM "$_er_pid" 2>/dev/null
      rm -f "$_er_out"
      return 1
    fi
    sleep 0.1
    _er_i=$((_er_i + 1))
  done
  wait "$_er_pid" 2>/dev/null
  cat "$_er_out"
  rm -f "$_er_out"
  return 0
}

# Prints a <session-history> block, or nothing. Kept as its own block rather
# than merged into <memory-context> because the provenance genuinely differs: a
# curated memory was written down on purpose, a transcript line is just
# something that was once said, possibly by a model, possibly wrongly.
episodic_recall_block() { # $1 = prompt, $2 = max snippets (default 2)
  _erb_prompt="${1:-}"
  _erb_n="${2:-2}"
  [ -n "$_erb_prompt" ] || return 0
  episodic_history_intent "$_erb_prompt" || return 0
  _erb_cli=$(episodic_cli) || return 0

  _erb_raw=$(_episodic_run "$_erb_cli" "$_erb_prompt" "$_erb_n" \
                           "${EPISODIC_DEADLINE_TENTHS:-20}") || return 0
  [ -n "$_erb_raw" ] || return 0

  # The CLI prints for humans and has no JSON mode, so the quoted snippet line is
  # extracted by shape. If that shape ever changes this yields nothing rather
  # than garbage, which is the correct failure for a hook.
  _erb_body=$(printf '%s\n' "$_erb_raw" \
    | sed -n 's/^[[:space:]]*"\(.*\)"[[:space:]]*$/- \1/p' \
    | head -n "$_erb_n")
  [ -n "$_erb_body" ] || return 0

  printf '<session-history>\n'
  printf 'From past conversations, not curated memory — treat as a lead to verify, not fact.\n'
  printf '%s\n' "$_erb_body"
  printf '</session-history>\n'
}
