#!/usr/bin/env bash
#
# phase-guard.sh — SpecFlow phase enforcement hook for Claude Code
#
# PreToolUse hook for Edit|Write. Reads the SpecFlow control plane,
# extracts current phase, classifies target file, allows or denies.
#
# Exit codes:
#   0 — allow the operation
#   2 — deny (stderr message fed to Claude)
#
# Fail-closed: missing control plane, missing phase, or parse errors → exit 2
# Exception: control plane (specflow.org) is always editable.

set -euo pipefail

CONTROL_PLANE="${CLAUDE_PROJECT_DIR:-.}/.specflow/specflow.org"

# --- Read stdin JSON (before control plane check so we can identify file) ---
INPUT=$(cat)

# --- Extract file path and tool name from stdin JSON ---
# Use python3 for reliable JSON parsing (available on macOS)
FILE_PATH=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    # file_path is in tool_input for Edit/Write
    ti = data.get('tool_input', {})
    print(ti.get('file_path', ''))
except:
    print('')
" 2>/dev/null || true)

TOOL_NAME=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('tool_name', ''))
except:
    print('')
" 2>/dev/null || true)

# Fail closed if we couldn't parse the file path
if [[ -z "$FILE_PATH" ]]; then
  echo "Phase guard: could not parse file path from tool input. Blocking edit." >&2
  exit 2
fi

# --- Check if target is the control plane (always allowed) ---
FILE_BASENAME=$(basename "$FILE_PATH")
if [[ "$FILE_BASENAME" == "specflow.org" ]] && [[ "$FILE_PATH" == */.specflow/* ]]; then
  exit 0
fi

# --- Allow writes to Claude Code operational directory (~/.claude/) ---
# Plan files, auto-memory, and session data live here.
# These are not project files and should not be phase-guarded.
if [[ -n "$HOME" ]] && [[ "$FILE_PATH" == "$HOME/.claude/"* ]]; then
  exit 0
fi

# --- Fail closed if control plane missing ---
if [[ ! -f "$CONTROL_PLANE" ]]; then
  echo "Phase guard: control plane not found at $CONTROL_PLANE. Blocking edit." >&2
  echo "Create .specflow/specflow.org with SPEC_FLOW_PHASE property to proceed." >&2
  exit 2
fi

# --- Extract phase from control plane ---
# Portable: no grep -P on macOS. Use sed to extract the phase value.
PHASE=$(sed -n 's/^[[:space:]]*:SPEC_FLOW_PHASE:[[:space:]]*\([^[:space:]]*\).*/\1/p' "$CONTROL_PLANE" 2>/dev/null | head -1)

# Fail closed if phase not found or empty
if [[ -z "$PHASE" ]]; then
  echo "Phase guard: SPEC_FLOW_PHASE not found in control plane. Blocking edit." >&2
  echo "Set SPEC_FLOW_PHASE in .specflow/specflow.org to proceed." >&2
  exit 2
fi

# --- Classify file path ---
# Returns: spec, todo, test, source, doc, unknown
classify_file() {
  local path="$1"
  local basename
  basename=$(basename "$path")

  # Spec files
  if [[ "$basename" == "spec.org" ]]; then
    echo "spec"
    return
  fi

  # TODO files
  if [[ "$basename" == "todo.org" ]]; then
    echo "todo"
    return
  fi

  # Test files: under tests/ directory or filename starts with test
  if [[ "$path" == */tests/* ]] || [[ "$basename" == test* ]]; then
    echo "test"
    return
  fi

  # Source code: common extensions under src/
  if [[ "$path" == */src/* ]]; then
    case "$basename" in
      *.el|*.py|*.js|*.ts|*.go|*.rs|*.rb|*.java|*.c|*.cpp|*.h)
        echo "source"
        return
        ;;
    esac
  fi

  # Documentation: .md or .org files not in src/
  case "$basename" in
    *.md|*.org)
      if [[ "$path" != */src/* ]]; then
        echo "doc"
        return
      fi
      ;;
  esac

  echo "unknown"
}

FILE_TYPE=$(classify_file "$FILE_PATH")

# --- Apply phase rules ---
deny() {
  local allowed="$1"
  echo "Phase violation: current phase is \"$PHASE\", but $TOOL_NAME was attempted on $(basename "$FILE_PATH")." >&2
  echo "$PHASE phase allows editing: $allowed." >&2
  echo "Change the phase in .specflow/specflow.org to proceed." >&2
  exit 2
}

case "$PHASE" in
  Plan)
    deny "nothing (read-only phase)"
    ;;

  Specify)
    if [[ "$FILE_TYPE" == "spec" ]]; then
      exit 0
    fi
    deny "spec.org files only"
    ;;

  Scaffold)
    if [[ "$FILE_TYPE" == "todo" ]]; then
      exit 0
    fi
    deny "todo.org files only"
    ;;

  Implement)
    exit 0
    ;;

  Validate)
    if [[ "$FILE_TYPE" == "test" ]]; then
      exit 0
    fi
    deny "test files only"
    ;;

  Document)
    if [[ "$FILE_TYPE" == "doc" ]] || [[ "$FILE_TYPE" == "spec" ]] || [[ "$FILE_TYPE" == "todo" ]]; then
      exit 0
    fi
    deny "documentation (.md, .org), spec.org, and todo.org files only"
    ;;

  *)
    # Unrecognized phase — fail closed
    echo "Phase guard: unrecognized phase \"$PHASE\". Blocking edit." >&2
    echo "Valid phases: Plan, Specify, Scaffold, Implement, Validate, Document." >&2
    exit 2
    ;;
esac
