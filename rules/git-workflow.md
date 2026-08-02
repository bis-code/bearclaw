# Git Workflow

## Commit Format (canonical — single source of truth across all repos)

```
<type>(<scope>): <description>

[optional body]

Generated with Claude Code
Co-Authored-By: Claude <noreply@anthropic.com>
```

Both trailer lines are required, in this order. **No robot emoji** on the Generated line — plain text. This is the canonical trailer; per-repo `.claude/rules/git-workflow.md` files that diverge should be normalized to this format (audit cycle 2026-05-16 finding CC-3, refined 2026-05-16 after workspace-wide signal that the no-emoji form is preferred).

Types: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`, `security`

## Rules

- One logical change per commit
- Tests pass before committing
- Stage specific files — never `git add -A` or `git add .`
- Feature branches: `issue/<number>-<short-slug>` from main
- One PR per issue
- Never force-push to main/master
