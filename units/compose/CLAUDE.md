# compose – Unit Rules

## Scope

The compose unit generates task-specific prompts for AI assistants.

### Owns

- Dispatcher command (`specflow-compose`)
- Task-specific compose commands (new-unit, edit-spec, new-feature, refactor)
- Template buffer creation and management
- `specflow-compose-mode` minor mode
- Prompt generation from user input
- Context file selection per task type

### Does NOT Own

- Control plane parsing (org-store)
- Context bundling (bundle)
- Conversation headers (hydrate)
- File editing or task execution
- Phase transitions

## Constraints

1. **Plan phase only** — Compose commands require Plan phase
2. **Prompt generation only** — Never write files, only generate text
3. **Org buffer interface** — Use standard Org-mode, no custom widgets
4. **Fast and clean** — Template buffer opens immediately, minimal UI
5. **Deterministic** — Same inputs produce same prompt
6. **Artifact preservation** — All prompts must include instructions to save planning artifacts

## Stop Conditions

STOP and ask for confirmation if:

- Implementation would require writing files (beyond kill-ring)
- New command beyond spec is needed
- Phase enforcement logic needs to change
- Prompt format significantly deviates from spec
- Dependencies on bundle or hydrate would be introduced

## Keybindings

Template buffers use:
- `C-c C-c` — Generate prompt and copy to kill-ring
- `C-c C-k` — Cancel and kill buffer

Do not change these keybindings without approval.

## Template Buffer Rules

- Headings are read-only (questions)
- User types under headings
- Empty required fields trigger warning
- Buffer killed after successful generation

## Generated Prompt Rules

All prompts MUST include:
1. Task description
2. Current state (unit, phase, parent chain)
3. Context files section
4. Requirements from user
5. Task-specific instructions
6. Phase rules
7. Artifact preservation instructions

## Dependencies

- `org-store` only
- No dependency on `hydrate` or `bundle`

## Implementation Notes

### Current Structure (pre-extraction)

- Compose code in `src/specflow.el` (lines 1211-1686)
- 5 interactive commands + minor mode
- 33 ERT tests in `tests/test-specflow-compose.el`
- README at `units/compose/README.md`

### Target Structure (post-extraction)

- `units/compose/src/specflow-compose.el` — compose implementation
- `units/compose/tests/test-specflow-compose.el` — compose tests

### Dependencies

Compose requires:
- `specflow-org-store` — control plane discovery and reading

Compose does NOT depend on hydrate or bundle (per spec).

## Phase

MVP complete: Plan → Specify → Scaffold → Implement → Validate → Document

Current: **Code extraction — Scaffold phase**
