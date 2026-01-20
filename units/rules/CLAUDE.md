# rules – Unit Rules

## Scope

This unit owns:
- Rule file discovery (`specflow-rules-find-file`)
- Rule parsing (`specflow-rules-load`)
- Rule filtering (`specflow-rules-for-phase`, `specflow-rules-mandatory`, `specflow-rules-by-tag`)
- Rule formatting (`specflow-rules-format-for-context`)
- The `rules.org` file format specification

This unit does NOT own:
- Bundle integration (bundle unit will call rules API)
- Hydrate integration (hydrate unit will call rules API)
- The root CLAUDE.md file (migration is a one-time task)
- Project-specific rule overrides (not in MVP)

## Constraints

1. **No external dependencies** — pure Elisp only, no network calls
2. **Deterministic** — same input always produces same output
3. **Read-only** — rules unit only reads rules.org, never writes
4. **Plists only** — return plists, no structs in MVP

## Stop Conditions

STOP and request approval if:
- Implementation would require writing to rules.org
- A new public function is needed beyond spec
- Bundle integration requires changes to bundle unit API
- Error handling behavior is ambiguous
- Rule format needs properties not in spec

## Phase Rules

### Implement Phase
- Write code strictly per spec
- Write ERT tests for each public function
- Do NOT add functions not in spec
- Do NOT add optional features

### Validate Phase
- Run all ERT tests
- Verify determinism tests pass
- Do NOT change behavior

### Document Phase
- Write README.md for unit
- Do NOT change code
