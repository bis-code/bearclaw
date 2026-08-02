---
description: Show local Claude Code spend (today / by-project / last-7d) from the cost-tracker metrics.
argument-hint: "[csv]"
---

# Cost Report

Run the local cost reporter and present its output verbatim, then add one line
of interpretation (e.g., which project dominates this week, or whether today is
tracking high vs the 7-day average).

```bash
"$HOME/.claude/bin/claude-cost-report" $ARGUMENTS
```

Notes:
- Costs are **estimates** from a per-1M-token rate table (the harness bills the
  authoritative amount). Treat them as burn-awareness signal, not invoicing.
- If output says "No cost data yet", the cost-tracker Stop hook simply hasn't
  written a row in this metrics dir yet — not an error.
- `/cost-report csv` exports the last 100 rows as CSV.
