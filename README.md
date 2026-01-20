# SpecFlow

Org-native, spec-driven, phase-gated workflow for AI-assisted software development.

## What is SpecFlow

AI assistants fail in predictable ways during development: jumping from vague intent to implementation, inferring unstated requirements, drifting scope, and losing track of project state. These aren't model bugs—they're workflow failures.

SpecFlow addresses this by making project state, intent, and constraints explicit using Org-mode as the source of truth. A control plane file tracks the current phase and active unit. AI assistants receive phase-specific instructions that tell them what actions are allowed and when to stop.

SpecFlow is a lightweight discipline plus Emacs tooling. It works for real projects, not just demos.

## Installation

**Prerequisites:** Emacs 27.1+

```bash
# Clone the repository
git clone https://github.com/tedmellors/specflow.git

# Or add to your load-path manually
```

```elisp
;; In your init.el
(add-to-list 'load-path "/path/to/specflow/src")
(require 'specflow)
```

## Quick Start

### 1. Create a control plane

Create `docs/specflow.org` in your project:

```org
#+TITLE: My Project – Control Plane

* Project
  :PROPERTIES:
  :SPEC_FLOW_PHASE: Plan
  :SPEC_FLOW_ACTIVE_UNIT: my-feature
  :END:

* Units

** my-feature
   :PROPERTIES:
   :SPEC: units/my-feature/spec.org
   :TODO: units/my-feature/todo.org
   :RULES: units/my-feature/CLAUDE.md
   :END:
```

### 2. Create a root todo.org

Create `todo.org` at your project root with a NEXT task:

```org
#+TITLE: Project TODO

* Active

** NEXT my-feature: Plan phase
   Design the feature architecture.
```

### 3. Generate a conversation header

```elisp
M-x specflow-hydrate-copy-header
```

This copies a header to your clipboard containing:
- Current phase and active unit
- Files the AI should consult
- Allowed actions for the phase
- The canonical NEXT task

### 4. Paste into your AI chat

Start your AI conversation with the header. The AI now knows:
- What phase you're in
- What it's allowed to do
- When to stop and ask

### 5. Work within phase constraints

Follow the phase rules. When ready to advance, update the control plane manually.

## Commands Overview

### hydrate – Conversation Framing

| Command | Description |
|---------|-------------|
| `specflow-hydrate-copy-header` | Copy conversation header to clipboard |
| `specflow-hydrate-preview-header` | Preview header in buffer |
| `specflow-hydrate-insert-header` | Insert header at point |
| `specflow-hydrate-insert-next` | Insert NEXT task only |
| `specflow-hydrate-open-control-plane` | Open control plane file |
| `specflow-hydrate-open-root-todo` | Open root todo.org |
| `specflow-hydrate-open-active-unit-spec` | Open active unit's spec |
| `specflow-hydrate-open-active-unit-todo` | Open active unit's todo |
| `specflow-hydrate-open-active-unit-rules` | Open active unit's CLAUDE.md |
| `specflow-hydrate-scan-buffer` | Scan for phase violations |
| `specflow-hydrate-scan-region` | Scan region for violations |

### bundle – Context Assembly

| Command | Description |
|---------|-------------|
| `specflow-bundle` | Bundle file paths (for Claude Code) |
| `specflow-bundle-text` | Bundle full file contents (for gptel/web) |

### org-store – Control Plane Operations

| Function | Description |
|----------|-------------|
| `specflow-org-store-find-control-plane` | Discover control plane file |
| `specflow-org-store-read-project-state` | Read phase and active unit |
| `specflow-org-store-read-unit` | Read a unit entry |
| `specflow-org-store-read-unit-registry` | Read all units |
| `specflow-org-store-write-property` | Update a property (minimal diff) |
| `specflow-org-store-validate-unit-pointers` | Validate file pointers |
| `specflow-org-store-validate-parent-chain` | Validate parent chain |

## Module Documentation

For detailed documentation on each module:

- [hydrate](units/hydrate/README.md) – Conversation header generation
- [bundle](units/bundle/README.md) – Context bundling for AI assistants
- [org-store](units/org-store/README.md) – Control plane parsing and writing

## The SpecFlow Workflow

Work proceeds through six phases:

| Phase | Allowed Actions |
|-------|-----------------|
| **Plan** | Summarize understanding, identify constraints, propose options. No code or specs. |
| **Specify** | Edit spec.org only. Define outcomes and requirements. |
| **Scaffold** | Write CLAUDE.md and todo.org. No implementation code. |
| **Implement** | Write code and tests strictly per spec. |
| **Validate** | Run tests, verify behavior. No code changes. |
| **Document** | Write documentation only. No code changes. |

Phase transitions are manual. Update the control plane's `SPEC_FLOW_PHASE` property when ready to advance.

## Project Structure

SpecFlow expects this structure:

```
your-project/
├── docs/
│   └── specflow.org      # Control plane (required)
├── todo.org              # Root tasks with NEXT (required)
└── units/
    └── <unit-name>/
        ├── spec.org      # Unit specification
        ├── todo.org      # Unit tasks
        ├── CLAUDE.md     # Unit rules for AI
        ├── src/          # Implementation
        ├── tests/        # Tests
        └── README.md     # Usage docs
```

The control plane registers units with pointers to their spec, todo, and rules files.

## Running Tests

```bash
emacs --batch -L src -L tests \
  -l specflow.el \
  -l test-specflow-org-store.el \
  -l test-specflow-bundle.el \
  -l test-specflow-hydrate.el \
  -f ert-run-tests-batch-and-exit
```

115 tests covering org-store (53), bundle (37), and hydrate (25).

## License

MIT
