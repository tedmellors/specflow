# org-store

Foundational SpecFlow module for control plane discovery, parsing, and minimal-diff writes.

## Overview

org-store provides the low-level Org file operations that all other SpecFlow modules depend on:

- **Discovery**: Find the control plane file (`docs/specflow.org`)
- **Reading**: Parse project state and unit registry
- **Writing**: Update properties with minimal diffs
- **Validation**: Verify file pointers and parent chains

## Installation

```elisp
(require 'specflow)
```

## Public API

### specflow-org-store-find-control-plane

Discover the control plane file.

```elisp
;; From current directory
(specflow-org-store-find-control-plane)
;; => "/path/to/project/docs/specflow.org"

;; From a specific directory
(specflow-org-store-find-control-plane "/path/to/project/src/foo/")
;; => "/path/to/project/docs/specflow.org"
```

**Discovery algorithm:**
1. Search upward from `default-directory` for `docs/specflow.org`
2. Stop at project root (`.git`, `.projectile`, or `.specflow-root`)
3. Fall back to `specflow-control-plane-path` variable if set
4. Signal `specflow-control-plane-not-found` if not found

**Configuration:**

```elisp
;; Set explicit fallback path
(setq specflow-control-plane-path "/path/to/control-plane.org")
```

### specflow-org-store-read-project-state

Read current project state from the control plane.

```elisp
(specflow-org-store-read-project-state)
;; => (:phase "Implement"
;;     :active-unit "org-store"
;;     :control-plane-path "/path/to/docs/specflow.org")

;; With explicit path
(specflow-org-store-read-project-state "/path/to/docs/specflow.org")
```

**Returns plist with:**
- `:phase` - Current phase (Plan, Specify, Scaffold, Implement, Validate, Document)
- `:active-unit` - Name of the active unit
- `:control-plane-path` - Absolute path to control plane file

**Errors:**
- `specflow-control-plane-not-found` - File not found
- `specflow-control-plane-malformed` - Missing `SPEC_FLOW_PHASE` or `SPEC_FLOW_ACTIVE_UNIT`

### specflow-org-store-read-unit

Read a single unit entry from the control plane.

```elisp
(specflow-org-store-read-unit "org-store")
;; => (:name "org-store"
;;     :dir "src/"
;;     :spec "units/org-store/spec.org"
;;     :todo "units/org-store/todo.org"
;;     :rules "units/org-store/CLAUDE.md"
;;     :parent "core"
;;     :children nil
;;     :context-refs nil)
```

**Returns plist with:**
- `:name` - Unit name
- `:dir` - Source directory (optional, may be nil)
- `:spec` - Path to spec file (required)
- `:todo` - Path to todo file (required)
- `:rules` - Path to rules file (required)
- `:parent` - Parent unit name (optional)
- `:children` - List of child unit names (optional)
- `:context-refs` - List of context reference paths (optional)

All paths are relative to project root.

**Errors:**
- `specflow-unit-not-found` - Unit not in registry
- `specflow-unit-malformed` - Missing SPEC, TODO, or RULES property

### specflow-org-store-read-unit-registry

Read all units from the control plane.

```elisp
(specflow-org-store-read-unit-registry)
;; => ((:name "core" :spec "units/core/spec.org" ...)
;;     (:name "org-store" :spec "units/org-store/spec.org" ...)
;;     (:name "bundle" :spec "units/bundle/spec.org" ...))
```

Returns a list of unit plists in document order. Returns empty list if no units defined.

### specflow-org-store-write-property

Write a property value with minimal diff.

```elisp
;; Update phase in control plane
(specflow-org-store-write-property
 "/path/to/docs/specflow.org"
 '("Project")
 "SPEC_FLOW_PHASE"
 "Validate")
;; => t

;; Update property on nested heading
(specflow-org-store-write-property
 "/path/to/docs/specflow.org"
 '("Units" "org-store")
 "DIR"
 "src/specflow/")
;; => t
```

**Parameters:**
- `FILE-PATH` - Absolute path to Org file
- `HEADING-PATH` - List of heading titles (e.g., `("Project")` or `("Units" "org-store")`)
- `PROPERTY` - Property name (string)
- `VALUE` - New value (string)

**Behavior:**
- Existing property: value replaced in-place
- Missing property: inserted at end of drawer
- Missing drawer: drawer created with property
- No other content modified (byte-for-byte)

**Errors:**
- `specflow-heading-not-found` - Heading path invalid
- `specflow-file-not-writable` - Cannot save file

### specflow-org-store-validate-unit-pointers

Validate that a unit's file pointers (SPEC, TODO, RULES) exist.

```elisp
(let ((unit (specflow-org-store-read-unit "org-store")))
  (specflow-org-store-validate-unit-pointers unit))
;; => t (if all files exist)

;; With explicit project root
(specflow-org-store-validate-unit-pointers unit "/path/to/project/")
```

**Errors:**
- `specflow-unit-pointer-invalid` - One or more files do not exist (lists all missing)

### specflow-org-store-validate-parent-chain

Validate and return the parent chain for a unit.

```elisp
;; Unit with parent: org-store -> core
(specflow-org-store-validate-parent-chain "org-store")
;; => ("core")

;; Unit with no parent
(specflow-org-store-validate-parent-chain "core")
;; => ()
```

Returns list of ancestor unit names from immediate parent to root.

**Errors:**
- `specflow-unit-not-found` - Unit does not exist
- `specflow-parent-not-found` - Parent references nonexistent unit or circular reference

## Error Handling

All errors inherit from `specflow-error`. Use `condition-case` to handle:

```elisp
(condition-case err
    (specflow-org-store-read-unit "nonexistent")
  (specflow-unit-not-found
   (message "Unit not found: %s" (cadr err)))
  (specflow-error
   (message "SpecFlow error: %s" (cadr err))))
```

**Error types:**

| Error | Condition |
|-------|-----------|
| `specflow-control-plane-not-found` | Discovery failed |
| `specflow-control-plane-malformed` | Missing required project properties |
| `specflow-unit-not-found` | Unit not in registry |
| `specflow-unit-malformed` | Unit missing required properties |
| `specflow-unit-pointer-invalid` | SPEC/TODO/RULES file missing |
| `specflow-parent-not-found` | Parent unit missing or circular |
| `specflow-heading-not-found` | Write target heading not found |
| `specflow-file-not-writable` | Cannot save file |

## Testing

Run the test suite:

```bash
emacs --batch -l ert -l src/specflow.el -l tests/test-specflow-org-store.el \
  -f ert-run-tests-batch-and-exit
```

53 tests covering all public functions, error conditions, and determinism.
