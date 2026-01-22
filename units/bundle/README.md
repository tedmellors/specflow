# bundle – SpecFlow Context Bundling

The bundle module assembles context for AI assistants. It gathers project state, the current NEXT task, parent chain documentation, and unit files into a single output suitable for pasting into Claude, GPT, or similar tools.

## Quick Start

```elisp
;; Load SpecFlow
(load-file "src/specflow.el")

;; Generate compact bundle with file paths (for Claude Code)
M-x specflow-bundle

;; Generate full bundle with file contents (for gptel/web Claude)
M-x specflow-bundle-text
```

## Output Modes

Bundle supports two output modes optimized for different AI tools:

| Mode | Command | Output | Use Case |
|------|---------|--------|----------|
| Paths | `M-x specflow-bundle` | File paths (~20 lines) | Claude Code (can read files) |
| Text | `M-x specflow-bundle-text` | Full content (~600 lines) | gptel, web Claude, external |

### Paths Mode (Default)

Outputs compact file paths that Claude Code can read directly. More efficient for tools with file access.

```
# SpecFlow Context Bundle (Paths)
# Generated: 2025-01-20T15:30:00

## Project State
Phase: Implement
Active Unit: bundle

## NEXT Task
** NEXT bundle: Document phase
   <full NEXT task content included>

## Parent: core
- SPEC: .specflow/units/core/architecture.org
- SPEC: .specflow/units/core/overview.org
- TODO: .specflow/units/core/todo.org

## Unit: bundle
- SPEC: .specflow/units/bundle/spec.org
- TODO: .specflow/units/bundle/todo.org

Read the files above for full context.
```

### Text Mode

Outputs full file contents. Use for AI tools without file access.

```
# SpecFlow Context Bundle (Text)
# Generated: 2025-01-20T15:30:00

## Project State
Phase: Implement
Active Unit: bundle

## NEXT Task
<content of first NEXT heading from .specflow/todo.org>

## Parent: core

### SPEC: .specflow/units/core/architecture.org
<file content>

### SPEC: .specflow/units/core/overview.org
<file content>

### TODO: .specflow/units/core/todo.org
<file content>

## Unit: bundle

### SPEC: .specflow/units/bundle/spec.org
<file content>

### TODO: .specflow/units/bundle/todo.org
<file content>
```

## Interactive Commands

### `M-x specflow-bundle`

Generates a context bundle in **paths mode** (default).

**Behavior:**
1. Reads project state from control plane
2. Extracts NEXT task from `.specflow/todo.org`
3. Lists parent chain file paths (SPEC, TODO)
4. Lists active unit file paths (SPEC, TODO)
5. Copies result to kill-ring
6. Displays result in `*SpecFlow Bundle*` buffer

### `M-x specflow-bundle-text`

Generates a context bundle in **text mode** (full content).

**Behavior:**
1. Reads project state from control plane
2. Extracts NEXT task from `.specflow/todo.org`
3. Gathers full parent chain content (SPEC, TODO files)
4. Gathers full active unit content (SPEC, TODO files)
5. Copies result to kill-ring
6. Displays result in `*SpecFlow Bundle*` buffer

## Programmatic API

### `specflow-bundle-context`

```elisp
(specflow-bundle-context &optional UNIT-NAME)
```

Returns a compact string with file paths (paths mode).

**Arguments:**
- `UNIT-NAME` (optional) — Bundle a specific unit instead of the active unit

**Returns:** String with file paths bundle

### `specflow-bundle-context-text`

```elisp
(specflow-bundle-context-text &optional UNIT-NAME)
```

Returns a comprehensive string with full file contents (text mode).

**Arguments:**
- `UNIT-NAME` (optional) — Bundle a specific unit instead of the active unit

**Returns:** String with full content bundle

### Examples

```elisp
;; Bundle the active unit (paths mode - default)
(specflow-bundle-context)

;; Bundle the active unit (text mode - full content)
(specflow-bundle-context-text)

;; Bundle a specific unit
(specflow-bundle-context "org-store")
(specflow-bundle-context-text "org-store")
```

### No-Timestamp Variants

For determinism tests:
- `specflow-bundle-context-no-timestamp`
- `specflow-bundle-context-text-no-timestamp`

## What Gets Bundled

| Section | Source | Description |
|---------|--------|-------------|
| Project State | Control plane | Current phase and active unit |
| NEXT Task | `.specflow/todo.org` | First heading marked NEXT with content |
| Parent Chain | Each ancestor unit | SPEC, TODO files (root-to-leaf order) |
| Active Unit | Current unit | SPEC, TODO files |

### Property Splitting

SPEC and TODO properties may contain space-separated paths:

```org
:SPEC: .specflow/units/core/architecture.org .specflow/units/core/overview.org
```

Bundle reads each file and includes them as separate entries.

## Error Handling

**Hard failures** (signal error):
- Control plane not found
- Specified unit not in registry

**Soft failures** (continue with placeholder):
- Missing file in SPEC/TODO → `<file not found: path/to/file>`
- No NEXT task found → `<no NEXT task found>`
- `.specflow/todo.org` missing → `<no root todo.org found>`

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
