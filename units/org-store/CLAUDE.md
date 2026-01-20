# org-store – Unit Rules

## Scope

This unit owns:
- Control plane discovery (`specflow-org-store-find-control-plane`)
- Project state reading (`specflow-org-store-read-project-state`)
- Unit registry reading (`specflow-org-store-read-unit`, `specflow-org-store-read-unit-registry`)
- Property writing with minimal diffs (`specflow-org-store-write-property`)
- Validation (`specflow-org-store-validate-unit-pointers`, `specflow-org-store-validate-parent-chain`)
- Workflow commands:
  - `specflow-phase-shift` — change SPEC_FLOW_PHASE in control plane
  - `specflow-add-root-task` — append TODO to root todo.org Active section
- Task management commands:
  - `specflow-refine-task` — generate prompt for Claude to improve backlog task
  - `specflow-activate-task` — same + promote to NEXT, demote current NEXT

This unit does NOT own:
- Phase semantics or transitions (core)
- Context bundling (bundle)
- UI/workspace management (hydrate)
- LLM integration

## Constraints

1. **No external dependencies** — pure Elisp only, no network calls, no LLM
2. **Deterministic** — same input always produces same output
3. **Minimal-diff writes** — only modify the target property line, nothing else
4. **No caching** — always re-read from disk in MVP
5. **Plists only** — return plists, no structs in MVP

## Stop Conditions

STOP and request approval if:
- Implementation would require caching
- Implementation would require full org-element AST parsing
- A new public function is needed beyond spec
- Error handling behavior is ambiguous
- Any change to control plane format is required

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

## Testing Requirements

All public functions must have ERT tests covering:
- Happy path
- Error conditions (hard failures)
- Edge cases (empty registry, missing optional properties)

Determinism tests are mandatory:
- Read twice → identical output
- Write same value twice → no file change on second write
