# Execution Discipline

How to *act on* a task. Sibling to `response-discipline.md` (how to *communicate*).

## Scope discipline
<!-- Provenance: most-corrected pattern in the 2026-06 friction audit, 4 project groups. -->

A request to "fix X" is a license to fix X — **not** to touch adjacent code.

- Before editing, state the affected files in one line. If the fix needs files
  outside that list, stop and say why before widening.
- **Never remove, hide, or rewrite** an existing screen, route, nav entry, entity,
  field, or endpoint not explicitly named for removal. A bug fix does not delete
  working features.
- Spotted an unrelated improvement? Propose it as a follow-up — don't fold it in.
- Prefer the smallest diff that satisfies the stated issue. Resist refactoring code
  you happen to be reading (YAGNI).

## Dead code — handle, don't ignore
<!-- Provenance: F15 — "I'll leave the dead one alone" correction, 2026-06-17.
     Inverse of Scope discipline: Scope protects reachable features named for keeping;
     this removes proven-dead code your own change orphaned. -->

- When you create a replacement and the old version becomes unreferenced, **do not
  leave the dead one in place.** Removing it IS part of the change, not a follow-up.
- **Verify-then-remove**, never delete on a hunch: grep for every reference (call
  sites, XcodeGen globs, tests, `@dsCard`/wire keys) to prove it's unreferenced, then
  remove it and let the build/tests confirm. Dispatch `refactor-cleaner` for
  non-trivial removals.
- If reachability is uncertain, it's not dead — leave it and say why.
- Don't accumulate `// TODO remove` / commented-out blocks / parallel old+new
  implementations. One live path; the orphan goes.

## Verify before reference
<!-- Provenance: F3 — 3 HIGH build breaks in one week from referencing symbols that
     didn't exist / editing files not opened with the Read tool. -->

- Before importing/referencing any module, constant, type, function, or feature flag,
  **grep to confirm it exists** in this codebase/version. Don't infer a symbol's name
  from convention.
- Before `Edit`, the file MUST have been opened with the **Read tool** this session.
  Bash `cat`/`grep`/`sed`/`head` do NOT satisfy the Edit contract.
- Detect the package manager from the lockfile: `pnpm-lock.yaml` → `pnpm`;
  `yarn.lock` → `yarn`; `package-lock.json` → `npm`; `go.sum` → `go`. Never
  `npm install` in a pnpm/yarn repo.

## Confirm before implement
<!-- Provenance: F7 — misread model/modality, across 3 project groups. -->

- For non-trivial UI, after scope locks, ask ONE question before writing: code-spec or
  design-first?
- After a domain-model correction, restate the corrected model in one sentence and wait
  for confirmation before re-implementing — don't silently re-code against your guess.
- Treat "make it X-driven" said mid-design as a clarification request, not approval.

## Planning prereq-check
<!-- Provenance: F8 — an unmet Apple Dev Program prerequisite sank 20-30% of a plan. -->

- Before planning a sub-project gated by an external prerequisite (paid API, vendor
  approval, billing account, Apple Dev Program), validate the prerequisite is reachable
  FIRST, and surface the risk before planning around it.
- After `superpowers:writing-plans`, surface phases + key decisions + the
  deploy/rollback approach for an explicit go-ahead before dispatching implementation.

## Verify source of truth
<!-- Provenance: F10 — staleness bites infra audits and post-merge audits. -->

- Local clones, ORM/LSP caches, and hand-maintained files (handoffs, memory) are
  **high-staleness**. Before acting on them, verify against the live source.
- SSH the actual host before infra audits; trust `go build ./...` over a gopls cache
  after a merge; grep actual values from code rather than citing a handoff/memory entry.

## Verification pairing
<!-- Provenance: June 2026 audit — only 20% verification rate before branch completion.
     Enforced by hooks/pretooluse-verification-pair.sh (unpaired finish denied once/session). -->

- Before `superpowers:finishing-a-development-branch`, invoke
  `superpowers:verification-before-completion` first. **Required pair** — finishing
  without the verification pass ships unverified behavior.

## Brainstorm scope-gate
<!-- Provenance: F13 — don't over-ceremony small changes. -->

- Single field / styling tweak / sub-component with no new data model → **skip** the full
  `superpowers:brainstorming` flow; a one-sentence design statement + thumbs-up is enough.
- Reserve the full brainstorming flow for new screens, domain-model changes, or
  multi-workstream work.
