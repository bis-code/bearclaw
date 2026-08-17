#!/usr/bin/env bats
# Tests for memory-doctor. Operates on fixture memory dirs.

DOCTOR="$BATS_TEST_DIRNAME/../memory-doctor.sh"

setup() {
  FIX="$(mktemp -d "${TMPDIR:-/tmp}/md.XXXXXX")"
  MD="$FIX/memory"; mkdir -p "$MD"
  printf -- '- [Indexed](indexed.md) — hook\n' > "$MD/MEMORY.md"
  printf -- '---\nname: indexed\ndescription: "a fact"\nmetadata:\n  type: project\n---\n\nbody\n' > "$MD/indexed.md"
}
teardown() { rm -rf "$FIX"; }

@test "report mode exits 0 and prints a header" {
  run bash "$DOCTOR" "$MD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"memory-doctor"* ]]
}

@test "missing dir is a clean error (exit 0, noted)" {
  run bash "$DOCTOR" "$FIX/nope"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no memory dir"* ]]
}

@test "report mode never writes (MEMORY.md unchanged)" {
  before="$(cat "$MD/MEMORY.md")"
  run bash "$DOCTOR" "$MD"
  [ "$(cat "$MD/MEMORY.md")" = "$before" ]
}

@test "scan_index flags an orphan entry (file not in MEMORY.md)" {
  printf -- '---\nname: orphan\ndescription: "x"\nmetadata:\n  type: project\n---\n' > "$MD/orphan.md"
  run bash "$DOCTOR" "$MD"
  [[ "$output" == *"ORPHAN: orphan.md"* ]]
}

@test "scan_index flags a dangling index link" {
  printf -- '- [Gone](missing.md) — hook\n' >> "$MD/MEMORY.md"
  run bash "$DOCTOR" "$MD"
  [[ "$output" == *"DANGLING: missing.md"* ]]
}

@test "scan_index flags malformed frontmatter (missing description)" {
  printf -- '---\nname: bad\nmetadata:\n  type: project\n---\n' > "$MD/bad.md"
  printf -- '- [Bad](bad.md) — hook\n' >> "$MD/MEMORY.md"
  run bash "$DOCTOR" "$MD"
  [[ "$output" == *"MALFORMED: bad.md"* ]]
}

@test "--apply removes a dangling index line" {
  printf -- '- [Gone](missing.md) — hook\n' >> "$MD/MEMORY.md"
  run bash "$DOCTOR" --apply "$MD"
  [ "$status" -eq 0 ]
  run grep -q "missing.md" "$MD/MEMORY.md"
  [ "$status" -ne 0 ]
  grep -q "indexed.md" "$MD/MEMORY.md"
}

@test "--apply appends a REVIEW stub for an orphan entry" {
  printf -- '---\nname: orphan-fact\ndescription: "the orphan hook"\nmetadata:\n  type: project\n---\n' > "$MD/orphan.md"
  run bash "$DOCTOR" --apply "$MD"
  grep -q '(orphan.md)' "$MD/MEMORY.md"
  grep -q 'REVIEW' "$MD/MEMORY.md"
  grep -q 'the orphan hook' "$MD/MEMORY.md"
}

@test "report mode does NOT modify the index even with issues present" {
  printf -- '- [Gone](missing.md) — hook\n' >> "$MD/MEMORY.md"
  run bash "$DOCTOR" "$MD"
  grep -q "missing.md" "$MD/MEMORY.md"
}

@test "scan_errors reports when ERRORS.md exceeds cap" {
  printf '# ERRORS\n\n## a\nx\n## b\ny\n## c\nz\n' > "$MD/ERRORS.md"
  ERRORS_CAP=3 run bash "$DOCTOR" "$MD"
  [[ "$output" == *"large journal"* ]]
}

@test "scan_errors says within cap for a small ERRORS.md" {
  printf '# ERRORS\n\n## only\na\n' > "$MD/ERRORS.md"
  run bash "$DOCTOR" "$MD"
  [[ "$output" == *"within cap"* ]]
}

@test "scan_errors never writes, even with --apply (no archive created)" {
  printf '# ERRORS\n\n## a\nx\n## b\ny\n## c\nz\n' > "$MD/ERRORS.md"
  before="$(cat "$MD/ERRORS.md")"
  ERRORS_CAP=3 run bash "$DOCTOR" --apply "$MD"
  [ "$(cat "$MD/ERRORS.md")" = "$before" ]
  [ ! -f "$MD/ERRORS.archive.md" ]
}

@test "scan_stale flags entries with a date older than STALE_DAYS (report-only)" {
  printf -- '---\nname: old\ndescription: "x"\nmetadata:\n  type: project\n---\nverified 2020-01-01\n' > "$MD/old.md"
  printf -- '- [Old](old.md) — hook\n' >> "$MD/MEMORY.md"
  STALE_DAYS=60 run bash "$DOCTOR" "$MD"
  [[ "$output" == *"STALE-CANDIDATE: old.md"* ]]
  grep -q "2020-01-01" "$MD/old.md"
}
