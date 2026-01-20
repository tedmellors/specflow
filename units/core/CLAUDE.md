# core – Unit Rules

## Scope

The core unit is the **project-level coordination unit**.

It owns:
- `architecture.org` — system architecture and component design
- `overview.org` — product purpose, principles, and constraints

It does NOT own:
- Implementation code (no src/ for core)
- Module-specific behavior (owned by child units)

## Constraints

1. **Documentation only** — core has no implementation code
2. **Parent to all modules** — org-store, bundle, hydrate, docs are children
3. **Authoritative constraints** — child units must respect core's documented invariants

## Phase

Core is permanently in a documented state.
No further phases apply (Plan/Specify/Scaffold/Implement/Validate/Document).

Child units reference core's architecture.org and overview.org as parent constraints.
