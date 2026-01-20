# bundle – SpecFlow Context Bundling

The bundle module assembles context for AI assistants. It gathers project state, the current NEXT task, parent chain documentation, and unit files into a single output suitable for pasting into Claude, GPT, or similar tools.

## Quick Start

```elisp
;; Load SpecFlow
(load-file "src/specflow.el")

;; Generate and display bundle for the active unit
M-x specflow-bundle
```

## Interactive Command

### `M-x specflow-bundle`

Generates a context bundle for the active unit (as defined in the control plane).

**Behavior:**
1. Reads project state from control plane
2. Extracts NEXT task from root `todo.org`
3. Gathers parent chain content (SPEC, TODO, RULES files)
4. Gathers active unit content (SPEC, TODO, RULES files)
5. Formats output with section delimiters
6. Copies result to kill-ring
7. Displays result in `*SpecFlow Bundle*` buffer

**Output:** The bundle is ready to paste into an AI assistant.

## Programmatic API

### `specflow-bundle-context`

```elisp
(specflow-bundle-context &optional UNIT-NAME)
```

Returns a formatted string containing the context bundle.

**Arguments:**
- `UNIT-NAME` (optional) — Bundle a specific unit instead of the active unit

**Returns:** String with formatted bundle content

**Errors:**
- `specflow-control-plane-not-found` — Control plane discovery failed
- `specflow-unit-not-found` — Specified unit not in registry

**Examples:**

```elisp
;; Bundle the active unit
(specflow-bundle-context)

;; Bundle a specific unit
(specflow-bundle-context "org-store")

;; Use the result
(let ((bundle (specflow-bundle-context)))
  (kill-new bundle)
  (message "Bundle copied: %d chars" (length bundle)))
```

### `specflow-bundle-context-no-timestamp`

Same as `specflow-bundle-context` but uses a fixed timestamp. Useful for determinism tests.

## What Gets Bundled

| Section | Source | Description |
|---------|--------|-------------|
| Project State | Control plane | Current phase and active unit |
| NEXT Task | Root `todo.org` | First heading marked NEXT with content |
| Parent Chain | Each ancestor unit | SPEC, TODO, RULES files (root-to-leaf order) |
| Active Unit | Current unit | SPEC, TODO, RULES files |

### Property Splitting

SPEC, TODO, and RULES properties may contain space-separated paths:

```org
:SPEC: units/core/architecture.org units/core/overview.org
```

Bundle reads each file and includes them as separate sections.

## Output Format

```
# SpecFlow Context Bundle
# Generated: 2025-01-19T15:30:00

## Project State
Phase: Implement
Active Unit: bundle

## NEXT Task
** NEXT bundle: Document phase
   ...task content...

## Parent: core

### SPEC: units/core/architecture.org
...file content...

### SPEC: units/core/overview.org
...file content...

### TODO: units/core/todo.org
...file content...

### RULES: units/core/CLAUDE.md
...file content...

## Unit: bundle

### SPEC: units/bundle/spec.org
...file content...

### TODO: units/bundle/todo.org
...file content...

### RULES: units/bundle/CLAUDE.md
...file content...
```

## Error Handling

**Hard failures** (signal error):
- Control plane not found
- Specified unit not in registry

**Soft failures** (continue with placeholder):
- Missing file in SPEC/TODO/RULES → `<file not found: path/to/file>`
- No NEXT task found → `<no NEXT task found>`
- Root `todo.org` missing → `<no root todo.org found>`

## Dependencies

Bundle depends only on org-store:
- `specflow-org-store-find-control-plane`
- `specflow-org-store-read-project-state`
- `specflow-org-store-read-unit`
- `specflow-org-store-validate-parent-chain`

## Limitations (MVP)

- No selective bundling (always outputs everything)
- No LLM compression
- No CONTEXT_REFS resolution
- No caching (re-reads files every time)

See `units/bundle/todo.org` for planned future enhancements.
