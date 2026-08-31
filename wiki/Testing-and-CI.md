How bearclaw is tested: one aggregate runner, four suite types, a structural identity gate, and CI on Linux to catch what a macOS machine can't.

## One entry point

```bash
./scripts/test-all.sh
```

That is the whole contract. It exits 0 only if every suite passes, and it is the same runner CI uses and the same one the pre-push hook calls — so a green local run means a green CI run for everything except platform differences (see the portability section below).

It prints `ok` or `FAIL` per suite, buffers each suite's output to a temp file and shows the first 20 lines only on failure, then ends with a `N passed, M failed` line and a list of failed suites. Nothing is skipped silently: a missing `bats` prints `skip (bats not installed)` explicitly.

## Suite layout

`test-all.sh` aggregates four lanes:

| Lane | Files | Run as |
|---|---|---|
| Shell | `hooks/*.test.sh`, `hooks/lib/*.test.sh`, `bin/*.test.sh` | `sh <file>` |
| Python | `hooks/lib/*.test.py` | `python3 <file>` |
| bats | `scripts/tests/*.bats` | `bats <file>` |
| Identity gate | `scripts/check-no-identity.sh` | directly |

The convention is **co-located tests**: a hook at `hooks/foo.sh` has its test at `hooks/foo.test.sh`, so the pair moves together and a missing test is visible in a directory listing. The `.test.sh` files are invoked as `sh <file>` and never executed directly, which is why `install.sh` deliberately skips them when setting executable bits.

Non-shell components are the exception and get a bats file instead. The current `scripts/tests/` suites:

| Suite | Covers |
|---|---|
| `guard-destructive.bats` | The Python destructive-command guard — which patterns deny and, importantly, which do not. |
| `install.bats` | `install.sh` behavior, including the guarantees about what it must not touch. |
| `settings-invariants.bats` | Invariants of `settings.json` **and** a meta-check over the test corpus (below). |
| `sessionstart-load-memory.bats` | The SessionStart memory loader. |
| `memory-doctor.bats` | The memory validator's report and `--apply` modes. |
| `audit-collect.bats` | The audit evidence collector. |

Every hook ships a test — that's a contribution requirement, not a convention. Tests exercise hooks through **environment seams** rather than fixtures: each hook accepts `*_DIR`, `*_BIN`, or `*_CMD` overrides (`CLAUDE_DISPATCH_STATE_DIR`, `SNAPSHOT_DIR`, `MEMORY_SEARCH_CMD`, `CLAUDE_COST_TRACKER_SYNC`, and so on) so a test never touches real state.

### The rule that came from breaking a real machine

From `CONTRIBUTING.md`, stated as a ground rule: **tests must never mutate real machine state.** The provenance is specific — an early test that merely *invoked* `install.sh` silently rebuilt the maintainer's real semantic-memory index and clobbered it. Nothing in the test looked like it touched memory; `install.sh` did it transitively.

So any test that exercises the memory system, directly or through `install.sh`, must set three variables:

```bash
MEMORY_BUILD_CMD=true               # no-ops the index build
GLOBAL_MEM_INDEX=<test-name>        # redirects away from the real index name
XDG_STATE_HOME=<tmp>                # keeps the capture store out of your real state dir
```

And this is **enforced, not requested**: `scripts/tests/settings-invariants.bats` scans every test file across all four lanes and fails the suite if one calls a memory-index hook, or invokes `install.sh`, without setting `MEMORY_BUILD_CMD`. `scripts/tests/install.bats` is the reference pattern to copy. A meta-test over the test corpus is unusual; it exists because the failure mode was invisible at review time.

## Pre-push lanes

`scripts/pre-push.sh` runs four lanes over the tracked tree before a push reaches the remote, so malformed config can't break the next session start:

| Lane | Command | Blocks? |
|---|---|---|
| JSON validity | `jq empty` on every tracked `*.json`, excluding `plugins/` runtime state | yes |
| Shell syntax | `bash -n` on every tracked `*.sh` | yes |
| Shellcheck | `shellcheck -S warning`, first 10 lines per file | **no** — advisory only |
| Test suite | `scripts/test-all.sh` | yes |

It skips gracefully when scripts are missing or `jq`/`bash` aren't on PATH, and on failure prints exactly what to do:

> `pre-push: blocking push — fix the issues above (or use --no-verify if you know what you're doing)`

`git push --no-verify` is the documented escape hatch for a deliberate choice. Note that the confirm gate independently treats `git --no-verify` as an outward-facing action requiring `CLAUDE_CONFIRMED=1` (see [[Hooks]]) — so an agent can't quietly bypass the lint.

Wire the hook up with a symlink from the checkout; see [[Installation]].

## The identity-leak gate

`scripts/check-no-identity.sh` fails if anything machine-specific or personally identifying reaches the tree. It runs in CI on every pull request and as the last lane of `test-all.sh`.

Four checks, all over `git ls-files` so untracked scratch files are ignored:

1. **Absolute home paths** — the macOS and Linux home roots followed by a username. Obvious fixture placeholders (`/home/user`, `/home/test`, `/home/runner`, and similar) are allowed so tests can still exercise path handling.
2. **Email addresses** — with a domain ending in a real-looking TLD that isn't a file extension, because `icon_512x512@2x.png` is a filename, not an address. The Anthropic no-reply address used in the commit trailer and `example.com`/`example.org` are allowed.
3. **IP addresses** — four octets. Loopback, unspecified, and broadcast are fine; anything else is somebody's host. Version-number-shaped strings are excluded by requiring four octets and dropping the common false positives.
4. **No second config-root split** — bearclaw is user-scope config for one computer and has no folder-scope concept, so it must not encode one. This check matches the *naming pattern* such a split would use, deliberately **not** the substring "work" alone, which appears in legitimate words the repo uses: workflow, workspace, worktree, network, framework, workaround.

### Why it contains no denylist of names

This is the most important design decision in the file, and it's recorded in its own header. An earlier version carried a literal denylist of the maintainer's employer, project, and host names — which meant **this public file published the exact strings it existed to keep out.** A public denylist of private terms is self-defeating.

So the checks here are **structural on purpose**: absolute paths from someone's machine, contact details, and network addresses. Those are the forms a leak takes regardless of whose fork it is, which makes this also the check a contributor wants running on their own PR. Anything name-specific belongs in a private pre-publish check, never in a public file.

Two implementation notes, both there to prevent the gate failing open and silently passing:

- `grep -H` forces the filename prefix even when the final `xargs` batch is a single file — without it, grep omits the prefix, breaking both the `file:line` output and the self-exclusion filter that depends on it.
- `grep -E` has no negative lookahead, so every exclusion is a `grep -v` filter on the results rather than a cleverer pattern. Keep it that way: an unsupported regex construct fails open and the check silently passes.

## CI

`.github/workflows/ci.yml` runs on pushes to `main` and on every pull request, on `ubuntu-latest`, installing `bats`, `shellcheck` and `jq`. Seven steps:

1. JSON validity over every tracked `*.json`
2. Shell syntax (`bash -n`) over every tracked `*.sh`
3. Shellcheck at warning level — advisory, `continue-on-error`
4. The identity gate
5. The full test suite
6. `install.sh --dry-run` into a temp root
7. A **real install into a temp root, run twice**, asserting `settings.json` exists and is *not* a symlink, that `.installed-from` records a `sha=`, and that a second run over the same destination still succeeds

Step 7 is what makes the installer's guarantees real rather than documentary: it proves the install copies rather than links, records where it came from, and is idempotent. It replaced an install/uninstall round-trip that asserted `settings.json` *was* a symlink — an assertion copy-on-install inverted. That step kept passing on the old contract until a push made CI say otherwise, which is the argument for keeping the workflow file in scope whenever installation changes.

## The macOS ↔ Linux portability trap

CI runs on Linux. If you develop on macOS, **CI is the only proof** for anything touching `date`, `stat`, `jq`, or shell builtins — the BSD and GNU tools differ in ways that pass locally and fail there.

The specific collisions, all documented in the code that works around them:

- **`stat -f`** means two different things: it's *format* on BSD and `--file-system` on GNU. Worse than a clean failure — on GNU the BSD invocation exits non-zero but still *leaks filesystem-mode output* to stdout, so a naive `|| true` fallback captures garbage instead of a timestamp. `scripts/audit-collect.sh` flags this at both call sites; `hooks/lib/memory-store.sh` avoids it entirely by using `find -mtime` instead of `stat`, calling it "exactly the portability trap that has bitten us."
- **`date` parsing** takes `-j -f <format>` on BSD and `-d <string>` on GNU. The portable form is to try one and fall back to the other, as `scripts/memory-doctor.sh` does.
- **Regex extensions** — `stop-memory-signal.sh` notes it stays in POSIX ERE only: no `\b`, no `\d`, no other GNU extensions, since those silently match differently or not at all.
- **Stock macOS bash is 3.2**, which errors on constructs newer bash accepts (`audit-collect.sh` calls out one such case under `set -u`).
- **`mktemp`** on macOS does not substitute the `X`s when a non-`X` suffix follows them.

Where a portable form exists, use it; where it doesn't, try-then-fallback and comment why. The pattern to copy is `statusline.sh`, which reads a file's mtime as `stat -f%m … || stat -c%Y … || echo 0` — BSD, then GNU, then a safe default.

## Contributing checklist

From `CONTRIBUTING.md`: nothing personal (run the identity gate before pushing); every hook ships a test through env seams; hooks are POSIX `sh`, under roughly 50ms, and fail open; anti-bloat, meaning you explain in the PR why you *need* it rather than why it might be nice; and tests never mutate real machine state. Then `./scripts/test-all.sh` must be green.

Commits follow `<type>(<scope>): <description>` with one logical change each — see the git-workflow rule on [[Rules]].
