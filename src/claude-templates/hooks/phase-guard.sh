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
# Fail-open: missing control plane, missing phase, or parse errors → exit 0

set -euo pipefail

CONTROL_PLANE="${CLAUDE_PROJECT_DIR:-.}/.specflow/specflow.org"

# --- Fail open if control plane missing ---
if [[ ! -f "$CONTROL_PLANE" ]]; then
  exit 0
fi

# --- Read stdin JSON ---
INPUT=$(cat)

# --- Extract phase from control plane ---
# Portable: no grep -P on macOS. Use sed to extract the phase value.
PHASE=$(sed -n 's/^[[:space:]]*:SPEC_FLOW_PHASE:[[:space:]]*\([^[:space:]]*\).*/\1/p' "$CONTROL_PLANE" 2>/dev/null | head -1)

# Fail open if phase not found or empty
if [[ -z "$PHASE" ]]; then
  exit 0
fi

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

# Fail open if we couldn't parse the file path
if [[ -z "$FILE_PATH" ]]; then
  exit 0
fi

# --- Classify file path ---
# Returns: control-plane, spec, todo, test, source, doc, unknown
classify_file() {
  local path="$1"
  local basename
  basename=$(basename "$path")

  # Control plane: always editable (phase transitions happen in any phase)
  if [[ "$basename" == "specflow.org" ]] && [[ "$path" == */.specflow/* ]]; then
    echo "control-plane"
    return
  fi

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

# --- Control plane is always editable (phase transitions) ---
if [[ "$FILE_TYPE" == "control-plane" ]]; then
  exit 0
fi

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
    # Unrecognized phase — fail open
    exit 0
    ;;
esac
