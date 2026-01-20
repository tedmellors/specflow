# docs – Unit Rules

## Scope

The docs unit owns user-facing documentation.

### Owns

- Root README.md (project entry point)
- Documentation structure and navigation

### Does NOT Own

- Unit-level READMEs (owned by org-store, bundle, hydrate)
- Internal design docs (overview.org, architecture.org owned by core)
- Code or implementation
- API documentation

## Constraints

1. **Documentation only** — No code in this unit
2. **Link, don't duplicate** — Reference unit READMEs instead of copying content
3. **Max 300 lines** — Root README should be concise
4. **Practical focus** — Installation and usage, not methodology deep-dive
5. **No emojis** — Keep professional tone

## Stop Conditions

STOP and ask for confirmation if:

- README exceeds 300 lines
- Content duplicates existing unit READMEs
- Scope expands beyond root README
- Internal architecture details would be exposed

## Target Audience

SpecFlow users — developers who want to use SpecFlow for their own projects.

Not: contributors to the SpecFlow codebase itself.

## Phase

Current: Scaffold
