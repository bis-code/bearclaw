# Secrets via 1Password (op)

Secrets flow through `op` only: env files hold `op://vault/item/field`
references, never values — run `op run --env-file=<f> -- <cmd>` (stdout
auto-masked). Never print a retrieved secret into files, logs, or the
transcript. Sessions are per-shell (`eval $(op signin)`); agent shells can't
reuse yours — unattended flows need `OP_SERVICE_ACCOUNT_TOKEN` (1k req/day).
Account details are machine-local — never commit them.
