# bundle – Unit Rules

## Scope

This unit owns:
- Context assembly (`specflow-bundle-context`, `specflow-bundle-context-text`)
- Interactive bundling commands (`specflow-bundle`, `specflow-bundle-text`)
- Dual output modes: paths (compact, for Claude Code) and text (full content)
- Parent chain resolution and content inclusion
- Space-separated property splitting (SPEC, TODO, RULES)
- Output formatting with section delimiters

This unit does NOT own:
- Control plane discovery or parsing (org-store)
- Property writing (org-store)
- LLM compression (deferred)
- CONTEXT_REFS resolution (deferred)
- UI/workspace management (hydrate)

## Constraints

1. **Depends on org-store only** — use org-store API for all control plane/unit reading
2. **Deterministic** — same input always produces same output (except timestamp)
3. **Resilient** — missing files produce warnings and placeholders, not errors
4. **No caching** — always re-read from disk
5. **No LLM calls** — MVP has no compression or AI integration

## Stop Conditions

STOP and request approval if:
- Implementation would require changes to org-store API
- A new public function is needed beyond spec
- Error handling behavior is ambiguous
- Output format needs significant changes from spec
- Any dependency on core, hydrate, or external services is needed

## Phase Rules

### Implement Phase
- Write code strictly per spec
- Write ERT tests for each public function
- Do NOT add functions not in spec
- Do NOT add LLM compression or CONTEXT_REFS

### Validate Phase
- Run all ERT tests
- Verify determinism tests pass
- Manual smoke test with M-x specflow-bundle (paths mode)
- Manual smoke test with M-x specflow-bundle-text (text mode)
- Do NOT change behavior

### Document Phase
- Write README.md for unit
- Do NOT change code

## Testing Requirements

All public functions must have ERT tests covering:
- Happy path (single files, multi-file SPEC)
- Parent chain inclusion
- Soft failures (missing files, no NEXT task)
- Determinism (bundle twice → same output)

Output mode tests:
- Paths mode returns compact output with file paths
- Text mode returns full file contents
- Both modes include NEXT task content

Interactive command tests:
- Kill-ring contains bundle content
- Buffer created with correct name
- Both `specflow-bundle` and `specflow-bundle-text` work correctly
