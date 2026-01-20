# compose – Task-Specific Prompt Generation

Generate task-specific prompts for AI-assisted development workflows.

## Quick Start

```elisp
;; Open dispatcher menu (requires Plan phase)
M-x specflow-compose

;; Or use direct commands
M-x specflow-compose-new-unit
M-x specflow-compose-edit-spec
M-x specflow-compose-new-feature
M-x specflow-compose-refactor
```

## Workflow

1. Ensure control plane is in **Plan** phase
2. Run a compose command (e.g., `M-x specflow-compose-new-unit`)
3. Fill in the template questions in the Org buffer
4. Press `C-c C-c` to generate prompt and copy to kill-ring
5. Paste into Claude or your AI assistant

## Commands

### Dispatcher

| Command | Description |
|---------|-------------|
| `specflow-compose` | Show menu of available compose actions |

### Direct Commands

| Command | Description |
|---------|-------------|
| `specflow-compose-new-unit` | Create prompt for new unit |
| `specflow-compose-edit-spec` | Create prompt for editing spec |
| `specflow-compose-new-feature` | Create prompt for new feature |
| `specflow-compose-refactor` | Create prompt for refactoring |

## Template Buffer

All compose commands open an Org-mode template buffer:

```
#+TITLE: New Unit

* Unit Name (required)
<type answer here>

* Parent (required)
<type answer here>

...

────────────────────────────────────────
C-c C-c  Generate prompt and copy to kill-ring
C-c C-k  Cancel
```

### Keybindings

| Key | Action |
|-----|--------|
| `C-c C-c` | Generate prompt, copy to kill-ring, show preview |
| `C-c C-k` | Cancel and kill buffer |

## Template Questions

### new-unit (8 questions)

| Question | Required |
|----------|----------|
| Unit Name | Yes |
| Parent | Yes (default: core) |
| Purpose (one line) | Yes |
| Problem it solves | Yes |
| In Scope | Yes |
| Out of Scope | No |
| Dependencies | No |
| Key Commands/Functions | No |

### edit-spec (4 questions)

| Question | Required |
|----------|----------|
| Which Unit | Yes (default: active unit) |
| What to Change | Yes |
| Why (rationale) | Yes |
| Constraints | No |

### new-feature (5 questions)

| Question | Required |
|----------|----------|
| Which Unit | Yes (default: active unit) |
| Feature Description | Yes |
| In Scope | Yes |
| Out of Scope | No |
| Affects Parent Architecture? | Yes (yes/no/unsure) |

### refactor (4 questions)

| Question | Required |
|----------|----------|
| Which Unit | Yes (default: active unit) |
| What to Refactor | Yes |
| Why (rationale) | Yes |
| Constraints | No |

## Generated Prompt Format

```
## Task: <task description>

### Current State
- Active unit: <unit>
- Phase: <phase>
- Parent chain: <chain or "none">

### Context Files
Read these files for context:
- <file1> (<description>)
- <file2> (<description>)

### Requirements
<structured requirements from answers>

### Instructions
<task-specific step-by-step instructions>

### Artifact Preservation
Save planning discussions and design decisions to:
  units/<unit>/temp-planning-artifacts.org

This preserves context across sessions. Delete after official docs are finalized.
```

## Context Files

Each command includes relevant context files:

| Command | Context Files |
|---------|---------------|
| new-unit | architecture.org, control plane, root todo.org |
| edit-spec | unit spec, parent specs, control plane |
| new-feature | unit spec, unit todo, parent specs (if affects parent) |
| refactor | unit spec, unit rules |

## Phase Enforcement

Compose commands **require Plan phase**.

If current phase is not Plan:
- Error message is displayed
- Template buffer is not opened

```
Compose commands require Plan phase. Current phase: Implement
```

To use compose commands, update the control plane to Plan phase first.

## Artifact Preservation

All generated prompts include instructions for Claude to save planning discussions to `temp-planning-artifacts.org`.

This ensures context is preserved across:
- Session boundaries
- Context window compaction
- Handoffs between conversations

Delete the artifact file after official documentation is finalized.

## Compose vs Hydrate

| Aspect | hydrate | compose |
|--------|---------|---------|
| Purpose | Continue workflow | Start new task |
| Output | Generic conversation header | Task-specific prompt |
| Phase | Any phase | Plan phase only |
| User input | None | Template questions |
| Use case | Resume AI session | Initiate planning task |
