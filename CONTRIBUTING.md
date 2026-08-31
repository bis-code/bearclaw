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
   failure.

   Two ways this gate dies quietly. Git ignores a hook symlink whose target is
   missing — silently, with no output. And if you keep a *private downstream* of
   this repo with its own pre-publish checks, the line above **replaces** them:
   link a wrapper of your own that runs `scripts/pre-push.sh` and those checks,
   never this file directly. Both failures look identical from outside — the
   push just succeeds — so when you audit the gate, check **what the link points
   at**, not merely that it resolves. A gate that runs the wrong script reports
   exactly as healthy as one that runs the right one.

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
   semantic-memory index and clobbered it. Any test that exercises the
   memory system — directly, or *transitively* through `install.sh` — MUST set:

   ```bash
   MEMORY_BUILD_CMD=true              # no-ops the index build
   GLOBAL_MEM_INDEX=<test-name>        # redirects away from the real index name
   GLOBAL_MEM_DIR=<tmp>                # ...and away from the real corpus
   XDG_STATE_HOME=<tmp>                # keeps memstore_init out of your real
                                        # ~/.local/state/claude-memory capture
                                        # store, and out of the real index dir
   ```

   `XDG_STATE_HOME` does double duty now that indexes live under
   `${XDG_STATE_HOME:-~/.local/state}/claude-memory/`: unset, a test that
   builds an index writes it next to the real ones.

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

**CI is the proof for anything platform-shaped.** The suite runs on Linux;
most contributors don't. `date`, `stat`, `jq` and shell builtins differ enough
between BSD and GNU that a green local run is evidence about your machine, not
about the project — so let CI report before calling such a change done.

The same holds for anything CI itself asserts. `.github/workflows/ci.yml`
pins the installer's contract — that `install.sh` **copies** rather than
symlinks, records provenance in `.installed-from`, and is idempotent on a
second run — and that file is easy to leave behind when a change is scoped to
`hooks/` or `install.sh`. If you change how installation works, open
`ci.yml` and check the assertions still describe it.

## Wiki

The [wiki](https://github.com/bis-code/bearclaw/wiki) is repo-sourced: pages
live in `wiki/` and `.github/workflows/wiki-sync.yml` publishes them on merge
to main. Edit `wiki/`, not the wiki UI — direct wiki edits are overwritten by
the next sync. This keeps wiki content PR-reviewable and inside the identity
gate.

## Commit format

`<type>(<scope>): <description>` — `feat`, `fix`, `refactor`, `test`, `docs`,
`chore`, `security`. One logical change per commit.
