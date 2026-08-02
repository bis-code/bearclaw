export const meta = {
  name: 'monthly-setup-audit',
  description: 'Analyze pre-collected Claude-setup evidence and synthesize a risk-grouped audit report',
  phases: [
    { title: 'Analyze', detail: '4 lane agents read evidence files' },
    { title: 'Synthesize', detail: 'opus dedups + writes the report' },
  ],
}

// args: { evidenceDir, reportPath, prevReportPath }
// Tolerate args arriving as a JSON-encoded string (some callers stringify it):
// string.evidenceDir would silently be undefined, yielding a false "no findings".
const A = (typeof args === 'string') ? JSON.parse(args) : (args || {})
const ev = A.evidenceDir
if (!ev) throw new Error('audit-workflow: args.evidenceDir is missing — refusing to run a false all-clear')

const FINDINGS_SCHEMA = {
  type: 'object',
  required: ['bucket', 'findings'],
  properties: {
    bucket: { type: 'string' },
    findings: {
      type: 'array',
      items: {
        type: 'object',
        required: ['title', 'evidence', 'severity', 'risk', 'fix_command', 'scope'],
        properties: {
          title: { type: 'string' },
          evidence: { type: 'string' },
          severity: { type: 'string', enum: ['high', 'med', 'low'] },
          risk: { type: 'string', enum: ['safe', 'destructive'] },
          fix_command: { type: 'string' },
          scope: { type: 'string' },
        },
      },
    },
  },
}

const RISK_RULES =
  'Classify each finding\'s risk: "safe" = reversible and low-blast-radius ' +
  '(prune a memory index line, archive ERRORS.md overflow, delete a known stale .bak). ' +
  '"destructive" = deletes/overwrites files, removes a repo config, or is otherwise ' +
  'hard to reverse. ANYTHING outside the Claude config directories MUST be risk "destructive" ' +
  'and scope "out-of-scope" — never "safe". fix_command must be an exact shell command or ' +
  'file edit. If the evidence file is missing or empty, return zero findings.'

const LANES = [
  { key: 'config', file: 'config.md', model: 'haiku',
    focus: 'CONFIG & ARTIFACT hygiene: unused/never-invoked agents/skills/rules, dead symlinks, .claude.json divergence, stale backups, debris, leaked processes/worktrees.' },
  { key: 'friction', file: 'friction.md', model: 'sonnet',
    focus: 'WORKFLOW FRICTION: recurring correction signatures, compaction frequency, and adoption gaps. The "## Dormancy" section pre-lists agents/skills DEFINED but NOT invoked this window — surface genuinely dead weight, but treat artifacts added this window as "not yet adopted", not dead. Interpret what repeatedly costs time.' },
  { key: 'memory', file: 'memory.md', model: 'haiku',
    focus: 'MEMORY hygiene: orphan/dangling index entries, dangling wikilinks, ERRORS.md over the 200-line cap, past-due/volatile dated notes.' },
  { key: 'cost', file: 'cost.md', model: 'sonnet',
    focus: 'COST & CROSS-REPO CONSISTENCY: token/cost burn, model-tier mismatches, per-repo git-workflow drift vs canonical, dead-repo configs, orphaned/auth-broken MCPs. From "## Enabled plugins", flag redundant plugins (duplicated by another plugin/skill) or project-specific plugins enabled globally. From "## MCP tools — prescribed vs USED", flag any configured server with 0 calls (dead mandate or broken tooling); from "## leann index health", flag STALE indexes.' },
]

phase('Analyze')
const lanes = (await parallel(LANES.map(l => () =>
  agent(
    `You are auditing the local Claude setup, lane: ${l.focus}\n\n` +
    `Read the evidence file at ${ev}/${l.file} with the Read tool. ` +
    `Lines beginning "_gap:" mark coverage gaps — note them but do not treat as findings.\n\n` +
    `${RISK_RULES}\n\nSet bucket="${l.key}".`,
    { label: `lane:${l.key}`, phase: 'Analyze', model: l.model, schema: FINDINGS_SCHEMA }
  )
))).filter(Boolean)

const presentBuckets = lanes.map(l => l.bucket)
const missingBuckets = LANES.map(l => l.key).filter(k => !presentBuckets.includes(k))

phase('Synthesize')
const summary = await agent(
  `You are the monthly Claude-setup audit synthesizer.\n\n` +
  `Lane findings (JSON):\n${JSON.stringify(lanes)}\n\n` +
  `Lanes that returned NO data (note as coverage gaps): ${missingBuckets.join(', ') || 'none'}.\n\n` +
  `If a previous report exists, read it for a delta: ${A.prevReportPath || '(none)'}.\n\n` +
  `Write a Markdown report with the Write tool to: ${A.reportPath}\n` +
  `Sections, in order:\n` +
  `1. Summary (3-5 bullets, the headline findings)\n` +
  `2. Findings by severity (high → low), each with evidence + scope\n` +
  `3. Fix-plan — three subsections: "Safe / reversible (apply on confirm)", ` +
  `"Destructive / manual review", "Out-of-scope (manual only — never auto-applied)". ` +
  `List the exact fix_command under each.\n` +
  `4. Delta vs last month (or "first run")\n` +
  `5. Coverage gaps (any missing lanes or evidence _gap: notes worth flagging)\n\n` +
  `Dedup overlapping findings across lanes.\n\n` +
  `NUMERIC FIDELITY: cite ONLY figures that appear verbatim in the lane findings' evidence. ` +
  `Never invent, round, or estimate counts — if a number is not in the evidence, do not state one.\n\n` +
  `Return a one-paragraph plain-text summary as your output (this goes back to the operator).`,
  { label: 'synthesize', phase: 'Synthesize', model: 'opus' }
)

return { reportPath: A.reportPath, summary, lanesRun: presentBuckets, missing: missingBuckets }
