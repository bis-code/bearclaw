# Global memory tier

Cross-cutting facts/lessons/failures that are true **regardless of which repo
you're in** — CLI/tool behavior, cross-project conventions, reusable failure
fixes. Loaded into every session via `hooks/sessionstart-load-memory.sh`.

Repo-specific knowledge goes in that repo's gitignored `.claude/memory/` instead.
See `rules/memory-hygiene.md` for the classification rule.

- `MEMORY.md` — index (one line per entry)
- `ERRORS.md` — global failure journal (newest first)
- `<slug>.md` — one fact per file, frontmatter: `name`, `description`, `metadata.type`

This directory ships **empty**. It fills up as you work: `sessionend-memory-capture.sh`
queues raw captures to `~/.local/state/claude-memory/_pending/`, and the
`memory-capture` skill distills them into entries here on your explicit accept.
Nothing is written without you approving it.
