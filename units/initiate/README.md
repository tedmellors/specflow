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

| File | Purpose |
|------|---------|
| `docs/specflow.org` | Control plane (phase, active unit, unit registry) |
| `CLAUDE.md` | Root AI assistant rules |
| `todo.org` | Root task driver with example NEXT task |
| `.specflow` | Project marker file |
| `units/core/` | Empty directory for core unit |

## Generated Control Plane

```org
#+TITLE: my-project – Control Plane

* Project
  :PROPERTIES:
  :SPEC_FLOW_PHASE: Plan
  :SPEC_FLOW_ACTIVE_UNIT: core
  :END:

* Units

** core
   :PROPERTIES:
   :DIR: src/
   :SPEC: units/core/spec.org
   :TODO: units/core/todo.org
   :RULES: units/core/CLAUDE.md
   :END:
```

## Generated CLAUDE.md

The root `CLAUDE.md` includes:
- SpecFlow philosophy summary
- Phase enforcement rules (Plan → Specify → Scaffold → Implement → Validate → Document)
- Task discovery instructions
- Stop conditions

## Generated todo.org

```org
* Active

** NEXT core: Plan phase
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
- `docs/specflow.org` already exists
- `.specflow` marker already exists

This prevents accidental overwrites.

## After Initialization

1. Review `docs/specflow.org`
2. Start with core: Plan phase
3. Draft `units/core/overview.org` (purpose, constraints)
4. Draft `units/core/architecture.org` (components, data flow)
5. Use `specflow-compose` to generate prompts for AI assistance

## Workflow Integration

```
specflow-initiate → Start new project
                    ↓
                Create scaffolding
                    ↓
                core: Plan phase
                    ↓
specflow-compose → Generate planning prompts
                    ↓
specflow-hydrate → Continue AI sessions
```
