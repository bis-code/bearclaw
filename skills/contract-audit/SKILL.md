---
name: contract-audit
description: Use to audit API contract drift between a project's layers — e.g. an iOS/Swift client vs a Go chi backend — comparing the endpoints the client calls against the routes the server serves (paths + methods) with file:line evidence on both sides. Reads/writes the project's .contract-audit.yml descriptor and ASKS the user when layers are unclear — never guesses. Triggers include "contract audit", "/contract-audit", "is the app calling routes that don't exist", or API drift after backend changes.
context: fork
allowed-tools: Read, Glob, Grep, Bash
---

# Contract Audit

Audit API contract drift across a project's layers: extract the endpoint set each layer defines or calls, normalize, diff, and report with evidence. The engine is generic — everything project-specific comes from the project's `.contract-audit.yml` descriptor, or from asking the user.

**Announce at start:** "I'm using the contract-audit skill to audit contract drift."

**Read-only, with ONE exception:** it writes/updates `.contract-audit.yml` in the target project (announced before writing). It NEVER modifies code, never stages, never commits — in the target project or anywhere.

**Core rule — never guess.** If the descriptor is missing or ambiguous, or extraction hits something dynamic, ASK the user (one question at a time) or file the item under *Unverifiable*. A confidently wrong audit is worse than a question.

## Step 1 — Locate the project + descriptor

Target project = cwd, unless the user names another path. Look for `.contract-audit.yml` at the project root.

- **Present** → validate: every `layers[].path` exists; every `type` is a v1 recipe below. Unknown type → tell the user which types v1 supports and stop (do not improvise an extractor).
- **Missing or incomplete** → interview the user, ONE question at a time:
  1. "Which directories/repos are the layers of this contract?"
  2. For each: "What is `<path>` — a Swift client, a Go chi backend, an OpenAPI spec?" (map to a v1 type)
  3. "What's the contract base path (e.g. `/v1`)?"
  4. "Any endpoints to ignore (health checks, metrics)?"
  5. For `swift-client` layers: "Where does the client define its endpoints (file or dir)?" → record under `notes`.

  Then WRITE the descriptor — announce: "Writing `.contract-audit.yml` so the next run skips the interview" — and continue.

Descriptor shape:

```yaml
contract_base: /v1
layers:
  - name: ios
    type: swift-client      # v1 types: swift-client | chi-routes | openapi-spec
    path: MyApp/
    notes: endpoints in MyApp/Networking/Endpoints.swift
  - name: backend
    type: chi-routes
    path: backend/
ignore:
  - /v1/health
```

## Step 2 — Extract per layer

Run each layer's recipe. Output per endpoint: `{method, path_template, file:line, confidence: certain|unverifiable}`.

### Recipe: `chi-routes` (Go)

1. Grep registrations across `*.go` under the layer path: `r.Get(`, `r.Post(`, `r.Put(`, `r.Patch(`, `r.Delete(`, `r.Head(`, `r.Options(`, `.Method(`, `.Handle(`, `.HandleFunc(`.
2. **Read the router-setup files — grep alone produces wrong paths.** Resolve `r.Route("/prefix", func(r chi.Router) {…})` nesting and `r.Mount("/prefix", sub)` so each route gets its FULL path; follow mounted subrouters into their defining files.
3. Record method + full path + file:line. chi params stay `{id}`.

### Recipe: `swift-client`

1. Find the API layer: descriptor `notes` first; else ask the user and record the answer back into the descriptor.
2. Extract endpoints: path string literals in the API layer; `URL`/`URLRequest` construction; enum-based routers (a `path` computed property is common). Method from `httpMethod` assignments or wrapper names (`get`/`post`/…).
3. Swift interpolation `\(x)` in a path → `{x}`. Paths built dynamically (cross-function concatenation, server-driven) → `confidence: unverifiable`.

### Recipe: `openapi-spec`

Read the declared spec file (YAML/JSON); endpoints = every `paths.<path>.<method>`. Highest-confidence source — when present, ALSO diff each implementation layer against it (spec = truth).

### Adding a layer type (the seam)

A new type = one new recipe subsection here (e.g. `angular-client`: HttpClient `get`/`post` calls + environment base URLs; `java-vertx`: `router.get("/…")` registrations). The flow does not change.

## Step 3 — Normalize (before diffing)

- Methods uppercase.
- Path params unified to `{x}`: `:id` → `{id}`, `\(id)` → `{id}`.
- Compare with `contract_base` stripped consistently (report full paths).
- Trailing slashes ignored. Apply `ignore` entries.

## Step 4 — Diff + report

Buckets:

1. **CRITICAL — client calls with no matching route** (runtime 404).
2. **MISMATCH — path matches, method or param count differs.**
3. **INFO — server routes never called by this client** (dead, or another client's).
4. **UNVERIFIABLE — dynamic constructions** (file:line) — review manually; ask the user about any that look load-bearing.

```
Contract Audit — <project> (<date>)
Layers: <a> (<type>) ↔ <b> (<type>)    base: <contract_base>

1) CRITICAL — client calls with no matching route
   - GET /v1/chargers/{id}   ios: Endpoints.swift:42 — no chi route found. Likely fix: backend
2) MISMATCH …
3) INFO …
4) UNVERIFIABLE …
```

Every finding cites file:line from BOTH sides where applicable + the likely side to fix. **Zero findings is a valid result — say so plainly.** Offer to save the report into the project's docs (user's call).

## Guardrails

- Minimum 2 layers; a layer yielding ZERO endpoints is a red flag — say so and ask the user where to look, never report a confident-but-empty diff.
- The ONLY write is `.contract-audit.yml`, announced first. No code edits, no staging, no commits.
- Findings need evidence (file:line). No evidence → it goes to Unverifiable, not CRITICAL.

## Related

- Design doc: `docs/superpowers/specs/2026-06-03-contract-audit-skill-design.md`
- `monthly-setup-audit` — setup health on a cadence; this skill = API-contract health, on demand.
