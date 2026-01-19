# SpecFlow – AI Assistant Rules


## Scope

This repository follows the **SpecFlow philosophy**:  
a **spec-driven, phase-gated workflow** for AI-assisted software development.

The system is organized into **units** (modules, services, components), each with:
- an explicit specification
- outcome-based TODOs
- unit-level constraints
- a well-defined lifecycle phase

This repository is intended for **real use**, not demos or throwaway prototypes.

“Production-ready” means:
- reliable within the stated scope
- testable and verifiable
- auditable where reasoning or decisions occur  
—not feature-complete or infrastructure-final.

---

## Control Plane Authority (MANDATORY)

The current operational state of this repo is defined by the SpecFlow control plane:
- `docs/specflow.org` (or the configured control plane path)

Before starting any work, you MUST:
1) Read the control plane
2) Identify the active unit and phase
3) Follow the phase rules for that phase

If there is a conflict between task focus in chat and the control plane,
the control plane is authoritative for: active unit, phase, and unit pointers.

## Task Discovery (MANDATORY)

Canonical NEXT task source is the repo root `todo.org`.

When asked "what is the NEXT actionable task":
1) Open `todo.org` at repo root.
2) Find the first heading marked `NEXT`.
3) Return that exact heading and its immediate bullets/subtasks as the actionable plan.
4) Do NOT use unit-level todo files to choose NEXT unless root `todo.org` explicitly points there.
5) If no `NEXT` exists, propose 1–3 candidate NEXT tasks and ask for confirmation.
If the NEXT task explicitly references a unit, treat that unit as the execution target,
but do NOT change the active unit in the control plane unless explicitly instructed.

## Parent Context (MANDATORY if declared)

Units may declare hierarchy in the control plane (e.g., `PARENT` / `CHILDREN` properties).

When working on a unit:

1) Read `docs/specflow.org` to identify the active unit and its `PARENT` chain (if any).
2) Before implementing or changing behavior in the unit, review parent unit specs/docs referenced by the control plane.
3) Treat parent unit constraints and invariants as authoritative.
4) If a child unit spec conflicts with a parent constraint, STOP and ask for resolution (do not implement).

### Response Header (MANDATORY)

At the start of any work response, include:
- Active unit:
- Phase:
- Parent chain (if any):
- Files consulted:

## Context References (CONTEXT_REFS) (OPTIONAL, BUT MUST OBEY IF PRESENT)

Units may declare additional context via a `CONTEXT_REFS` property in the control plane.

Semantics:
- `PARENT` chain docs/specs are **authoritative constraints**.
- `CONTEXT_REFS` are **advisory context** to read for additional background, examples, or rationale.
- If `CONTEXT_REFS` conflicts with parent constraints or the unit spec, parent/spec win.

When working on a unit:
1) Read the control plane entry for the active unit.
2) If `CONTEXT_REFS` is present, read those references before implementing changes.
3) Treat them as context only (not requirements) unless the unit spec explicitly promotes them to requirements.


## Bootstrapping the Master TODO (when missing) (PROMPTED ONLY)

If the repo does not yet have a root `todo.org`, do **NOT** create one automatically.

Only generate an initial root `todo.org` when I explicitly request it
(e.g., “bootstrap the master todo” / “create root todo.org”).

When prompted to bootstrap:

- Treat this as a Scaffold task.
- Do NOT write implementation code.
- Read the highest-level context (overview/architecture and any parent chain docs).
- Produce a root `todo.org` that:
  - defines phases (Plan → Specify → Scaffold → Implement → Validate → Document)
  - lists major units/modules in dependency order
  - contains exactly ONE `NEXT` task that is actionable and outcome-based
- STOP and request approval before making any other project changes.

## Documentation Pipeline (PROMPTED ONLY)

This repo uses a top-down documentation pipeline:

1) `overview.org` (intent)  
2) `architecture.org` (structure)  
3) root `todo.org` (execution plan)  
4) unit specs/todos (scoped implementation)

These artifacts are created or updated **only when explicitly requested**.
Do not generate or modify them “opportunistically.”

### overview.org (Intent Layer)

`overview.org` defines:
- the product/system goal
- user workflow and success criteria
- scope boundaries and non-goals
- key invariants and constraints
- glossary / shared vocabulary (optional)

When I ask to draft or revise `overview.org`:
- stay high-level (no module internals)
- prefer clear constraints and examples
- capture open questions explicitly
- STOP and request review before moving to architecture

### architecture.org (Structure Layer)

`architecture.org` derives from `overview.org` and defines:
- system decomposition into units/modules
- data flow / state model
- interfaces/contracts (as needed)
- phase plan: what gets built first and why
- validation strategy (how we know it works)

When I ask to draft or revise `architecture.org`:
- do not invent new product requirements beyond overview
- keep it implementable (but still high-level)
- STOP and request review before moving to master todo

### root todo.org (Execution Layer)

The root `todo.org` is the canonical task driver.
It is generated from `overview.org` + `architecture.org` **only when prompted**.

When I ask to bootstrap or revise root `todo.org`:
- produce a phase-structured roadmap
- include exactly ONE `NEXT` task
- keep tasks outcome-based (Given/When/Then style)
- preserve DONE history if updating an existing file
- STOP and request approval before proceeding to unit work

### Unit-level work (Child Units)

Child units are created/refined only after root `todo.org` explicitly points to them.

When root `todo.org` points to a unit:
- consult parent chain specs (if declared) before implementation
- create/update unit `spec.org` and `todo.org` per phase rules
- do not skip phases or jump to implementation


## Master TODO → Unit Handoff (MANDATORY)

When the root `todo.org` NEXT task points to a specific unit:

1) Treat that unit as the execution target (do not change control plane unless instructed).
2) Read parent chain specs/docs first (PARENT), then the unit spec/todo/rules.
3) Perform work only for the current phase:
   - Plan: design/options/questions only
   - Specify: edit unit `spec.org` only
   - Scaffold: edit unit `CLAUDE.md` + `todo.org` only
   - Implement: code + tests only
   - Validate/Document: no behavior changes
4) STOP and request approval at the end of each phase deliverable.


## Global Rules

1. **One unit at a time.**  
   Only edit files within the active unit unless explicitly authorized.

2. **Interface discipline.**  
   Cross-unit interfaces or contracts must live in a designated location  
   (e.g. `docs/interfaces/`, `interfaces/`, or equivalent).

   To change an interface:
   - Update the interface definition
   - Write an ADR explaining the change
   - **STOP. Do not implement. Wait for explicit approval.**

   If approval is not granted, explain why the change is required and halt.

3. **Spec-driven development.**  
   Each unit has a spec (1–2 pages max).  
   Implement **only** what is explicitly stated.  
   Do not infer or extend requirements.

   If behavior is unclear or missing, update the spec or ask before proceeding.

4. **Smallest possible change.**  
   Prefer the minimal diff needed to satisfy the spec or active TODO.  
   Do not refactor, rename, or reorganize code unless required.  
   No temporary, backward-incompatible, or partial interface changes.

5. **Testing is mandatory.**  
   Every behavior change must include corresponding test updates.  
   Tests should cover only the changed or newly specified behavior.  
   Do not rewrite unrelated tests or introduce new frameworks.

6. **Auditability where applicable.**  
   For analytical, ranking, comparison, or recommendation outputs:
   - Claims must cite evidence
   - Comparisons must explain rationale
   - Outputs must be traceable to inputs  

   Do not add unnecessary explanation for purely mechanical code.

7. **Avoid scope creep.**  
   Do not introduce new units, workflows, abstractions, or architectural patterns
   unless explicitly requested.

8. **TODOs describe outcomes, not tasks.**  
   When writing TODOs, avoid:
   - “Implement X”
   - “Refactor Y”

   Prefer:
   - “Given A, when B, then C”
   - “Function returns structure {…}”
   - “Latency p95 < 200ms on dataset D”
   - “Unit tests cover parser edge cases: …”

9. **Phase violations require confirmation.**  
   If an action would violate the current phase, **STOP and ask for confirmation**.

---

## Control Plane & Source of Truth

This repository uses an **Org-mode control plane**  
(e.g. `docs/specflow.org`) to store:
- the active unit
- the current phase
- canonical pointers to specs, TODOs, and rules

Org files (`.org`) are the authoritative source for:
- specifications
- planning documents
- ADRs
- TODOs

Markdown (`.md`) files are created **only** when explicitly requested
(e.g. README files for external users).

---

## Unit Structure (Canonical)


Each unit follows this structure (names may vary by project):
<unit>/
    CLAUDE.md # Unit-specific scope, constraints, stop conditions
    spec.org # Specification (source of truth)
    todo.org # Outcome-based tasks
    src/ # Implementation
    tests/ # Tests
    README.md # Usage docs (written after validation)

---

## Operating Procedure (MANDATORY)

Before starting any task:
1. Identify the active unit
2. Identify the current phase from the control plane
3. State the phase explicitly
4. Follow the phase enforcement rules below

When working on a task:

1. Read:
   - project overview / architecture docs (if relevant)
   - unit `spec.org`
   - unit `todo.org` (active `NEXT`)
   - unit `CLAUDE.md`
   - unit `README.md` (if it exists)

2. Work **only** within the active unit unless explicitly authorized.

3. If an interface change is required:
   - Propose the change
   - Update the interface definition
   - Draft an ADR
   - **STOP and wait for approval**

4. When finished:
   - Update tests
   - Update specs/docs if behavior changed
   - Commit changes (or provide exact git commands)
   - Mark the `NEXT` task as DONE
   - Summarize:
     - what changed and why
     - files touched
     - tests run and results
   - Propose the next `NEXT` task

---

## Phase Enforcement (MANDATORY)

Each unit progresses strictly through:

**Plan → Specify → Scaffold → Implement → Validate → Document**

Claude MUST obey the following rules:

### Plan
- Do NOT write or modify code
- Do NOT write specs or TODOs
- ONLY:
  - summarize understanding
  - identify constraints
  - list open design questions
  - propose options
  - request confirmation

### Specify
- ONLY edit `spec.org`
- Do NOT write code
- Ask for review before proceeding

### Scaffold
- ONLY write `CLAUDE.md` and `todo.org`
- Do NOT write implementation code

### Implement
- Write code and tests strictly per spec and TODOs

### Validate / Document
- Do NOT change behavior
- ONLY validate, test, or document existing behavior

---

### Plan Mode Output Contract

When in **Plan** phase, output must include:

1. Summary of unit responsibility (1–2 paragraphs)
2. Known constraints (from spec / architecture)
3. Open design questions
4. Proposed next actions
5. Explicit request for confirmation before proceeding

---

## Bug / Runtime Issue Protocol

When a bug or runtime issue is discovered:

1. **Investigate only**
   - Identify root cause
   - Do NOT modify code

2. **Document the issue**
   - Add a high-level entry to the project TODOs
   - Add a detailed entry to the unit `todo.org`, including:
     - symptoms
     - root cause
     - proposed fix (with rationale)

3. **STOP and present findings**
   - What went wrong
   - Why it happened
   - Proposed fix (and alternatives)
   - Files that would change

4. **Wait for explicit approval** before implementing

This applies even to “simple” or obvious fixes.

---

## Current Focus

Check the control plane (`specflow.org`) or top-level `todo.org`
for the active `NEXT` task and current phase.

