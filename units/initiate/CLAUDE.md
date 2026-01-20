# initiate – Unit Rules

## Scope

The initiate unit bootstraps new SpecFlow projects.

### Owns

- `specflow-initiate` command
- Control plane template
- Root CLAUDE.md template
- Root todo.org template
- Project marker file creation

### Does NOT Own

- Unit specification writing (user does this)
- Git initialization
- Interactive configuration
- Post-initialization workflows

## Constraints

1. **One command** — Only `specflow-initiate`, no variants
2. **Non-interactive** — No prompts, fully automatic
3. **Idempotent detection** — Refuse if project already exists
4. **Minimal scaffolding** — Only essential files
5. **No overwrites** — Never overwrite existing files
6. **Derived naming** — Project name from directory, not user input

## Stop Conditions

STOP and ask for confirmation if:

- Additional files beyond spec are proposed
- Interactive prompts are suggested
- Git integration is requested
- Overwrite behavior is needed
- Template content changes significantly

## File Creation Rules

All files must be created atomically:
- Check all preconditions first
- Create all files or none
- Display clear success/failure message

## Template Rules

Templates use `<project-name>` placeholder:
- Replaced with directory name at runtime
- Directory name is sanitized (spaces → hyphens, lowercase)

## Dependencies

- None (standalone unit)
- Uses only basic Emacs file operations

## Implementation Notes

- All initiate code lives in `src/specflow.el` (lines 1652-1807)
- 1 interactive command defined
- 21 ERT tests in `tests/test-specflow-initiate.el`
- README at `units/initiate/README.md`

## Phase

This unit has completed: Plan → Specify → Scaffold → Implement → Validate → Document

Status: **Complete** (MVP)
