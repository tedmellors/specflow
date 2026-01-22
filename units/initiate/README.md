# initiate – Project Bootstrapping

Bootstrap new SpecFlow projects with minimal scaffolding.

## Quick Start

```elisp
;; Navigate to your new project directory
cd ~/projects/my-new-project

;; In Emacs, run:
M-x specflow-initiate
```

## What It Creates

| Path | Purpose |
|------|---------|
| `.specflow/specflow.org` | Control plane (phase, active unit, unit registry) |
| `.specflow/todo.org` | Root task driver with example NEXT task |
| `.specflow/rules.org` | Operational rules (generates CLAUDE.md) |
| `.specflow/units/docs/spec.org` | Docs unit specification |
| `.specflow/units/docs/todo.org` | Docs unit tasks |
| `src/<project>/` | Base directory for future unit source code |
| `tests/` | Test directory |
| `CLAUDE.md` | Generated from rules.org (if hydrate available) |

## Directory Structure

```
my-project/
├── .specflow/
│   ├── specflow.org           # Control plane
│   ├── todo.org               # Root tasks
│   ├── rules.org              # Operational rules
│   └── units/
│       └── docs/
│           ├── spec.org       # Docs unit spec
│           └── todo.org       # Docs unit tasks
├── src/
│   └── my-project/            # Source base (empty)
├── tests/                     # Test directory (empty)
└── CLAUDE.md                  # Generated from rules.org
```

## Generated Control Plane

```org
#+TITLE: my-project – Control Plane

* Project
  :PROPERTIES:
  :SPEC_FLOW_PHASE: Plan
  :SPEC_FLOW_ACTIVE_UNIT: docs
  :END:

* Units

** docs
   :PROPERTIES:
   :SPEC: .specflow/units/docs/spec.org
   :TODO: .specflow/units/docs/todo.org
   :END:

The docs unit defines project-level documentation: overview, architecture,
and cross-cutting constraints. It has no source directory.
```

## The Docs Unit

New projects start with a `docs` unit that produces project documentation:

- `overview.org` – Project purpose, goals, success criteria, non-goals
- `architecture.org` – System structure, components, data flow

The docs unit has **no source directory** – it produces Org files, not code.
This ensures every project begins with clear documentation before implementation.

## Generated rules.org

The `.specflow/rules.org` includes:
- SpecFlow philosophy summary
- Control plane authority
- Task discovery rules
- Phase enforcement (Plan → Specify → Scaffold → Implement → Validate → Document)
- Global rules for AI assistants

Run `M-x specflow-hydrate-rules` to regenerate `CLAUDE.md` from rules.org.

## Generated todo.org

```org
* Active

** NEXT docs: Plan phase
   Define the project architecture and initial unit structure.

   - Draft overview.org (purpose, constraints, success criteria)
   - Draft architecture.org (components, data flow, dependencies)
   - Identify first implementation unit
```

## Project Name

The project name is derived from the directory name:
- Spaces → hyphens
- Converted to lowercase

Example: `My Cool Project` → `my-cool-project`

## Preconditions

`specflow-initiate` will refuse to run if:
- `.specflow/specflow.org` already exists

This prevents accidental overwrites.

## After Initialization

1. Review `.specflow/specflow.org`
2. Start with docs: Plan phase
3. Draft `overview.org` (purpose, constraints)
4. Draft `architecture.org` (components, data flow)
5. Use `specflow-compose` to generate prompts for AI assistance

## Workflow Integration

```
specflow-initiate → Start new project
                    ↓
                Create .specflow/ scaffolding
                    ↓
                docs: Plan phase
                    ↓
specflow-compose → Generate planning prompts
                    ↓
                Draft overview.org & architecture.org
                    ↓
                Define first implementation unit
                    ↓
specflow-hydrate → Continue AI sessions
```

## CLAUDE.md Generation

If `specflow-hydrate-rules` is available when `specflow-initiate` runs,
CLAUDE.md is generated automatically. Otherwise, run it manually:

```elisp
M-x specflow-hydrate-rules
```

This generates CLAUDE.md from `.specflow/rules.org`.
