# hydrate – Unit Rules

## Scope

The hydrate unit provides *AI conversation framing*.

### Owns

- Conversation header generation
- NEXT task extraction from root todo.org
- Phase-specific allowed actions templates
- Navigation helpers (open control plane, unit files)
- Phase violation scanning commands

### Does NOT Own

- Context bundling (owned by bundle)
- Control plane parsing/writing (owned by org-store)
- Window/buffer/workspace management
- Automatic file modifications
- LLM integration (gptel, Claude API)

## Constraints

1. **Depends on org-store only** — No bundle dependency for MVP
2. **No continuous hooks** — Explicit scan commands only
3. **Deterministic output** — Same inputs produce same header
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

- All hydrate code lives in `src/specflow.el` (lines 886-1210)
- 11 interactive commands defined
- 25 ERT tests in `tests/test-specflow-hydrate.el`
- README at `units/hydrate/README.md`

## Phase

This unit has completed: Plan → Specify → Scaffold → Implement → Validate → Document

Status: **Complete** (MVP)
