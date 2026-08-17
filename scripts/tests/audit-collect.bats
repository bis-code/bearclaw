#!/usr/bin/env bats
# Tests for the audit collector. Each test points the collector at a fixture
# tree, never the real ~/.claude.

setup() {
  FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/audit-fix.XXXXXX")"
  mkdir -p "$FIXTURE/setup/agents" "$FIXTURE/setup/skills/foo" \
           "$FIXTURE/setup/rules" "$FIXTURE/setup/hooks" \
           "$FIXTURE/home" "$FIXTURE/work-home"
  export SETUP_REPO="$FIXTURE/setup"
  export CLAUDE_HOME="$FIXTURE/home"
  export CLAUDE_WORK_HOME="$FIXTURE/work-home"
  export CLAUDE_PROJECT_ROOTS="$FIXTURE"
  export WINDOW_DAYS=30 MAX_HITS=50
  source "$BATS_TEST_DIRNAME/../audit-collect.sh"
}

teardown() { rm -rf "$FIXTURE"; }

@test "sourcing does not run main (no stray output)" {
  run bash -c "source '$BATS_TEST_DIRNAME/../audit-collect.sh'; echo SOURCED_OK"
  [ "$status" -eq 0 ]
  [ "${lines[-1]}" = "SOURCED_OK" ]
}

@test "main prints an existing evidence dir as last line" {
  run bash "$BATS_TEST_DIRNAME/../audit-collect.sh"
  [ "$status" -eq 0 ]
  out_dir="${lines[-1]}"
  [ -d "$out_dir" ]
  [ -f "$out_dir/config.md" ]
  [ -f "$out_dir/friction.md" ]
  [ -f "$out_dir/memory.md" ]
  [ -f "$out_dir/cost.md" ]
  rm -rf "$out_dir"
}

@test "collect_config lists agents by basename" {
  echo "x" > "$SETUP_REPO/agents/code-reviewer.md"
  run collect_config
  [ "$status" -eq 0 ]
  [[ "$output" == *"- code-reviewer"* ]]
}

@test "collect_config flags dead symlinks" {
  ln -s /nonexistent/path "$CLAUDE_HOME/deadlink"
  run collect_config
  [[ "$output" == *"DEAD"* ]]
  [[ "$output" == *"deadlink"* ]]
}

@test "collect_config reports missing dirs as gaps, not failures" {
  rm -rf "$SETUP_REPO/agents"
  run collect_config
  [ "$status" -eq 0 ]
  [[ "$output" == *"_gap:"* ]]
}

@test "collect_friction counts transcripts in window" {
  mkdir -p "$CLAUDE_HOME/projects/proj-a"
  printf '%s\n' '{"type":"user","message":"no, that is wrong, do it again"}' \
    > "$CLAUDE_HOME/projects/proj-a/s1.jsonl"
  run collect_friction
  [ "$status" -eq 0 ]
  [[ "$output" == *"transcript files in window"* ]]
}

@test "collect_friction surfaces correction signatures" {
  mkdir -p "$CLAUDE_HOME/projects/proj-a"
  printf '%s\n' '{"type":"user","message":"no, that is wrong"}' \
    > "$CLAUDE_HOME/projects/proj-a/s1.jsonl"
  run collect_friction
  [[ "$output" == *"Correction signatures"* ]]
}

@test "collect_friction handles missing projects dir as a gap" {
  rm -rf "$CLAUDE_HOME/projects"
  run collect_friction
  [ "$status" -eq 0 ]
  [[ "$output" == *"_gap:"* ]]
}

@test "collect_friction counts only real compaction boundaries, not the word" {
  mkdir -p "$CLAUDE_HOME/projects/proj-c"
  printf '%s\n' '{"isCompactSummary":true}' > "$CLAUDE_HOME/projects/proj-c/real.jsonl"
  printf '%s\n' '{"text":"we should compact this code"}' \
    > "$CLAUDE_HOME/projects/proj-c/wordonly.jsonl"
  run collect_friction
  [[ "$output" == *"sessions with compaction boundary: 1"* ]]
}

@test "collect_friction excludes subagent transcripts from correction scan" {
  mkdir -p "$CLAUDE_HOME/projects/proj-d/subagents"
  printf '%s\n' '{"type":"user","message":"no, that is wrong"}' \
    > "$CLAUDE_HOME/projects/proj-d/subagents/sa.jsonl"
  run collect_friction
  [ "$status" -eq 0 ]
  [[ "$output" != *subagents* ]]
}

@test "collect_memory flags orphan memory files (not in index)" {
  export MEMORY_DIR="$FIXTURE/mem"
  mkdir -p "$MEMORY_DIR"
  printf '%s\n' "- [Indexed](indexed.md) — hook" > "$MEMORY_DIR/MEMORY.md"
  echo "fact" > "$MEMORY_DIR/indexed.md"
  echo "fact" > "$MEMORY_DIR/orphan.md"
  run collect_memory
  [ "$status" -eq 0 ]
  [[ "$output" == *"ORPHAN"* ]]
  [[ "$output" == *"orphan.md"* ]]
}

@test "collect_memory orphan check matches the parenthesized link, not a loose substring" {
  export MEMORY_DIR="$FIXTURE/mem"
  mkdir -p "$MEMORY_DIR"
  printf '%s\n' "- [Beta](beta.md) — hook" > "$MEMORY_DIR/MEMORY.md"
  echo "fact" > "$MEMORY_DIR/beta.md"
  echo "fact" > "$MEMORY_DIR/eta.md"   # NOT indexed; 'eta.md' is a substring of 'beta.md'
  run collect_memory
  [ "$status" -eq 0 ]
  [[ "$output" == *"ORPHAN (no index line): eta.md"* ]]
}

@test "collect_memory flags dangling index links" {
  export MEMORY_DIR="$FIXTURE/mem"
  mkdir -p "$MEMORY_DIR"
  printf '%s\n' "- [Gone](missing.md) — hook" > "$MEMORY_DIR/MEMORY.md"
  run collect_memory
  [[ "$output" == *"DANGLING: missing.md"* ]]
}

@test "collect_memory reports ERRORS.md line count" {
  export MEMORY_DIR="$FIXTURE/mem"; export ERRORS_FILE="$FIXTURE/mem/ERRORS.md"
  mkdir -p "$MEMORY_DIR"; printf 'a\nb\nc\n' > "$ERRORS_FILE"
  run collect_memory
  [[ "$output" == *"ERRORS.md lines: 3"* ]]
}

@test "collect_cost flags per-repo git-workflow drift vs canonical" {
  echo "CANON" > "$SETUP_REPO/rules/git-workflow.md"
  mkdir -p "$FIXTURE/repoX/.claude/rules"
  echo "DIFFERENT" > "$FIXTURE/repoX/.claude/rules/git-workflow.md"
  run collect_cost
  [ "$status" -eq 0 ]
  [[ "$output" == *"DRIFT"* ]]
  [[ "$output" == *"repoX"* ]]
}

@test "collect_cost lists MCP servers from .mcp.json" {
  printf '%s' '{"mcpServers":{"deep-think":{}}}' > "$CLAUDE_HOME/.mcp.json"
  run collect_cost
  [[ "$output" == *"deep-think"* ]]
}

@test "collect_cost notes missing stats-cache as a gap" {
  run collect_cost
  [ "$status" -eq 0 ]
  [[ "$output" == *"_gap:"* ]]
}

@test "collect_config debris section emits no per-dir line when no debris dirs exist" {
  # empty CLAUDE_HOME fixture — none of handoffs/plans/tasks/teams/session-env exist
  run collect_config
  [ "$status" -eq 0 ]
  [[ "$output" == *'Debris counts'* ]]
  [[ "$output" != *'handoffs:'* ]]
}

@test "is_mcp_referenced: true when repo path appears in an .mcp.json" {
  printf '%s' '{"mcpServers":{"x":{"args":["/Users/x/youtube-mcps/foo-mcp/build/index.js"]}}}' \
    > "$FIXTURE/a.mcp.json"
  run is_mcp_referenced "/Users/x/youtube-mcps/foo-mcp" "$FIXTURE/a.mcp.json"
  [ "$status" -eq 0 ]
}

@test "is_mcp_referenced: false when repo path is absent" {
  printf '%s' '{"mcpServers":{}}' > "$FIXTURE/a.mcp.json"
  run is_mcp_referenced "/Users/x/dead-repo" "$FIXTURE/a.mcp.json"
  [ "$status" -ne 0 ]
}

@test "collect_memory marks .md files ORPHAN when MEMORY.md is absent" {
  export MEMORY_DIR="$FIXTURE/mem-noindex"
  mkdir -p "$MEMORY_DIR"
  echo 'fact' > "$MEMORY_DIR/some-entry.md"   # no MEMORY.md on purpose
  run collect_memory
  [ "$status" -eq 0 ]
  [[ "$output" == *'ORPHAN'* ]]
  [[ "$output" == *'some-entry.md'* ]]
  [[ "$output" == *'Dangling index links'* ]]
}

@test "audit-collect has no hardcoded user path" {
  REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  run grep -c 'baicoianuionut' "$REPO/scripts/audit-collect.sh"
  [ "$output" = "0" ]
}

@test "audit-collect honours CLAUDE_PROJECT_ROOTS" {
  REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  run grep -c 'CLAUDE_PROJECT_ROOTS' "$REPO/scripts/audit-collect.sh"
  [ "$status" -eq 0 ]
  [ "$output" != "0" ]
}

@test "heal-settings resolves the repo from its own location, not a hardcoded path" {
  REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  run grep -c 'som/personal-projects' "$REPO/hooks/sessionstart-heal-settings.sh"
  [ "$output" = "0" ]
}
