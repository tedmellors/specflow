# hydrate – AI Conversation Framing

Generate conversation headers for AI-assisted development sessions.

## Quick Start

```elisp
;; Copy header to clipboard
M-x specflow-hydrate-copy-header

;; Paste into your AI chat

;; Regenerate CLAUDE.md from rules
M-x specflow-hydrate-rules
```

## Commands

### Header Commands

| Command | Description |
|---------|-------------|
| `specflow-hydrate-copy-header` | Copy header to kill-ring |
| `specflow-hydrate-preview-header` | Preview in read-only buffer |
| `specflow-hydrate-insert-header` | Insert at point (with safety prompt) |
| `specflow-hydrate-insert-next` | Insert NEXT task only |

### Navigation Helpers

| Command | Description |
|---------|-------------|
| `specflow-hydrate-open-control-plane` | Open `.specflow/specflow.org` |
| `specflow-hydrate-open-root-todo` | Open `.specflow/todo.org` |
| `specflow-hydrate-open-active-unit-spec` | Open unit spec.org |
| `specflow-hydrate-open-active-unit-todo` | Open unit todo.org |

### CLAUDE.md Generation

| Command | Description |
|---------|-------------|
| `specflow-hydrate-rules` | Generate CLAUDE.md from `.specflow/rules.org` |

The `specflow-hydrate-rules` command:
1. Finds the project root via control plane discovery
2. Loads rules from `.specflow/rules.org`
3. Formats them as markdown with clean headings
4. Writes `CLAUDE.md` at the project root

### Scan Commands

| Command | Description |
|---------|-------------|
| `specflow-hydrate-scan-buffer` | Scan buffer for phase violations |
| `specflow-hydrate-scan-region` | Scan region for phase violations |

## Header Format

The generated header includes:

```
Active unit: <unit-name>
Phase: <phase>
Parent chain: <parents or "none">

Files to consult:
- .specflow/specflow.org (control plane)
- .specflow/todo.org (root todo)
- <unit-spec> (unit SPEC)
- <unit-todo> (unit TODO)
- <parent-specs> (parent: <name>)

Allowed actions in this phase:
- <phase-specific actions>

STOP conditions:
- If an action would violate the current phase, STOP and ask for confirmation.
- If an interface change is required, STOP and ask for approval.

Canonical NEXT task:
<next-task-heading-and-body>
```

## Workflow

1. Run `M-x specflow-hydrate-copy-header`
2. Paste header at start of AI conversation
3. AI now has phase context and knows:
   - What files to consult
   - What actions are allowed
   - When to STOP and ask
   - What task to work on

## Phase-Specific Actions

| Phase | Allowed Actions |
|-------|-----------------|
| Plan | Summarize understanding, identify constraints, propose options |
| Specify | Edit spec.org only |
| Scaffold | Write CLAUDE.md and todo.org only |
| Implement | Write code and tests per spec |
| Validate | Run tests, verify behavior, no changes |
| Document | Write documentation only |

## Safe Buffers

Insert commands skip confirmation prompts for buffers matching:
- `*scratch*`
- Names containing "gptel", "claude", "chat"

## Scanning

Scan commands detect potential phase violations:

- **Plan/Specify/Scaffold**: Flags code blocks, diff hunks, implementation phrases
- **Validate/Document**: Flags behavioral change language
- **Implement**: No warnings (code is expected)

Results appear in minibuffer or `*SpecFlow Warnings*` buffer.
