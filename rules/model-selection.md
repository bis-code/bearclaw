# Model Selection (for Agent / sub-agent dispatch)

<!-- Trimmed 2026-08-16 (S4): five-dimensions, open-questions, and workspace-
override sections cut (full text in git history). -->

| Task shape | Default model | Don't go below | Override up when |
|---|---|---|---|
| Read / enumerate / extract (recap, file listing, inventory, grep search) | `haiku` | — | The "extract" needs interpretation, not retrieval. |
| Execute (TDD, refactor, Playwright, CI, doc, PR, test interpretation) | `sonnet` | `sonnet` | The execution path is irreversible, security-touching, or architecture-deciding. |
| Reason / design / synthesize (architecture, security review, audit, design brief) | `opus` | `sonnet` (only if scope is genuinely bounded) | n/a — this IS the high tier. |
| Final gate before irreversible action (merge, deploy, rollout) | `opus` | `sonnet` | n/a. |

## Four sticky meta-rules
<!-- Provenance: F11 — 73% of dispatches were general-purpose (June 2026 audit).
Enforced by hooks/pretooluse-dispatch-gate.sh (matched-trigger GP dispatch
denied once/session; missing model: reminded once/session). -->

1. **Always set `model` explicitly on Agent calls** — omitting it inherits the
   spawner tier (often opus → silent cost inflation). Same for **Workflow
   `agent()` calls**: default workflow sub-agents to `sonnet` (they're the bulk
   of token spend); reserve `opus` for the few review/synthesis agents.
2. **Pick the model for the hardest part of the job and keep it for the agent's
   lifetime** — never split one job into a haiku-then-opus chain (prompt-cache
   startup makes mid-job swaps costly).
3. **In parallel dispatch, mix models** — ≤2 opus agents per 5-way fan-out.
4. **Set `subagent_type` to the most specific named agent, not
   `general-purpose`** (`language-reviewer`, `build-error-resolver`, …) — tuned
   instructions + scoped tools win. GP is the fallback only when nothing fits.

## Anti-patterns (refuse on sight)

- `opus` for pure enumeration/recap — haiku.
- `haiku` for architecture/security/judgment work — sonnet or opus.
- Mixing models within one sub-agent's lifetime.
- Omitting `model:` on Agent calls (spawner inheritance).
- `opus` inside a tight `/loop`.
- `general-purpose` when a named agent fits.
