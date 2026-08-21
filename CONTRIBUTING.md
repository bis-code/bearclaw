# Contributing

Contributions welcome — especially new agents, skills, and hooks.

## Ground rules

1. **Nothing personal.** `scripts/check-no-identity.sh` runs in CI and blocks any
   PR containing absolute user paths, org names, or emails. Run it before pushing.
2. **Wire the pre-push gate once, after cloning.** `install.sh` deliberately
   never touches your git hooks, so nothing links it for you:

   ```sh
   ln -s ../../scripts/pre-push.sh .git/hooks/pre-push
   ```

   It runs the JSON/shell lint and the full suite, and blocks the push on
   failure. Note git ignores a hook symlink whose target is missing — silently,
   with no output — so if the gate ever stops firing, check that link resolves.

3. **Every hook ships a test.** A hook at `hooks/foo.sh` needs `hooks/foo.test.sh`
   that exercises it via env seams (see existing hooks — they all take
   `*_DIR` / `*_BIN` overrides so tests never touch your real state). A hook
   that isn't shell (e.g. `hooks/guard-destructive.py`) gets a `.bats` file in
   `scripts/tests/` instead — see `scripts/tests/guard-destructive.bats`.
4. **Hooks are POSIX `sh`, not bash.** They run on every session start; keep them
   under ~50ms and make them fail open — a broken hook must never block work.
5. **Anti-bloat.** If a thing isn't load-bearing for everyday use, it doesn't ship.
   Explain in the PR why you need it, not why it might be nice.
6. **Tests must never mutate real machine state.** This bit us: an early test
   that merely invoked `install.sh` silently rebuilt this maintainer's real
   `leann` semantic-memory index and clobbered it. Any test that exercises the
   memory system — directly, or *transitively* through `install.sh` — MUST set:

   ```bash
   MEMORY_BUILD_CMD=true              # no-ops the leann index build
   GLOBAL_MEM_INDEX=<test-name>        # redirects away from the real index name
   XDG_STATE_HOME=<tmp>                # keeps memstore_init out of your real
                                        # ~/.local/state/claude-memory capture store
   ```

   This is **enforced, not merely requested**: `scripts/tests/settings-invariants.bats`
   scans every test file (`hooks/*.test.sh`, `hooks/lib/*.test.sh`,
   `scripts/tests/*.bats`, `bin/*.test.sh`) and fails the suite if one calls a
   memory-index hook, or invokes `install.sh`, without setting
   `MEMORY_BUILD_CMD`. See `scripts/tests/install.bats` for the reference
   pattern.

## Before you push

```bash
./scripts/test-all.sh
```

That runs every suite plus the identity gate. It must be green.

## Wiki

The [wiki](https://github.com/bis-code/bearclaw/wiki) is repo-sourced: pages
live in `wiki/` and `.github/workflows/wiki-sync.yml` publishes them on merge
to main. Edit `wiki/`, not the wiki UI — direct wiki edits are overwritten by
the next sync. This keeps wiki content PR-reviewable and inside the identity
gate.

## Commit format

`<type>(<scope>): <description>` — `feat`, `fix`, `refactor`, `test`, `docs`,
`chore`, `security`. One logical change per commit.
