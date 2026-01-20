# hydrate – Unit Rules

## Scope

The hydrate unit provides *AI conversation framing*.

### Owns

- Conversation header generation
- NEXT task extraction from root todo.org
- Phase-specific allowed actions templates
- Navigation helpers (open control plane, unit files)
- Phase violation scanning commands
- CLAUDE.md generation from rules.org

### Does NOT Own

- Context bundling (owned by bundle)
- Control plane parsing/writing (owned by org-store)
- Window/buffer/workspace management
- Automatic file modifications
- LLM integration (gptel, Claude API)

## Constraints

1. **Depends on org-store and rules** — No bundle dependency
2. **No continuous hooks** — Explicit scan commands only
3. **Deterministic output** — Same inputs produce same header (modulo timestamps)
4. **Safe defaults** — Copy/preview safe; insert prompts for unknown buffers
5. **Text templates** — Phase actions are text, not Elisp constants

## Stop Conditions

STOP and ask for confirmation if:

- Changes to org-store API are required
- New public command beyond spec is needed
- Header format changes significantly
- Bundle or core dependency would be introduced
- Automatic file writes are proposed
- Continuous monitoring hooks are proposed

## Implementation Notes

### File Structure

- `units/hydrate/src/specflow-hydrate.el` — hydrate implementation
- `units/hydrate/tests/test-specflow-hydrate.el` — 29 ERT tests
- `units/hydrate/README.md` — user documentation

### Dependencies

Hydrate requires:
- `specflow-org-store` — control plane discovery and reading
- `specflow-rules` — loading and formatting operational rules

Hydrate does NOT depend on bundle (per spec). Uses local `specflow-hydrate--split-paths` helper.

### Commands

12 interactive commands:
- 4 header commands (copy, preview, insert-header, insert-next)
- 5 navigation helpers (open control-plane, root-todo, unit-spec, unit-todo, unit-rules)
- 2 scan commands (scan-buffer, scan-region)
- 1 generation command (hydrate-rules)

## Phase

MVP complete: Plan → Specify → Scaffold → Implement → Validate → Document

Code extraction: **Complete** (2026-01-20)
