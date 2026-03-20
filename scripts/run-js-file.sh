#!/bin/bash
set -e

# Run a JavaScript helper with the most appropriate runtime for the selected package manager.
# - Prefer Bun when Bun is explicitly selected or auto-detected from lockfiles
# - Otherwise prefer Node.js, with Bun as a fallback runtime when Node is unavailable

SCRIPT_PATH="$1"
shift || true

if [ -z "$SCRIPT_PATH" ]; then
  echo "❌ Error: JavaScript script path is required"
  exit 1
fi

CURRENT_DIR="$PWD"
WORKSPACE_DIR="${WORKSPACE_ROOT:-${GITHUB_WORKSPACE:-$CURRENT_DIR}}"
RAW_SELECTED_MANAGER="${PACKAGE_MANAGER:-auto}"
SELECTED_MANAGER="$(printf '%s' "$RAW_SELECTED_MANAGER" | tr '[:upper:]' '[:lower:]')"

if [ "$SELECTED_MANAGER" != "auto" ] && [ "$SELECTED_MANAGER" != "npm" ] && [ "$SELECTED_MANAGER" != "yarn" ] && [ "$SELECTED_MANAGER" != "pnpm" ] && [ "$SELECTED_MANAGER" != "bun" ]; then
  echo "❌ Error: Invalid PACKAGE_MANAGER value '$RAW_SELECTED_MANAGER'. Must be 'auto', 'npm', 'yarn', 'pnpm', or 'bun'"
  exit 1
fi

has_lockfile() {
  local dir="$1"
  local filename="$2"
  [ -n "$dir" ] && [ -f "$dir/$filename" ]
}

detect_package_manager() {
  if [ "$SELECTED_MANAGER" != "auto" ]; then
    echo "$SELECTED_MANAGER"
    return
  fi

  if has_lockfile "$CURRENT_DIR" "bun.lockb" || has_lockfile "$WORKSPACE_DIR" "bun.lockb"; then
    echo "bun"
  elif has_lockfile "$CURRENT_DIR" "bun.lock" || has_lockfile "$WORKSPACE_DIR" "bun.lock"; then
    echo "bun"
  elif has_lockfile "$CURRENT_DIR" "pnpm-lock.yaml" || has_lockfile "$WORKSPACE_DIR" "pnpm-lock.yaml"; then
    echo "pnpm"
  elif has_lockfile "$CURRENT_DIR" "yarn.lock" || has_lockfile "$WORKSPACE_DIR" "yarn.lock"; then
    echo "yarn"
  else
    echo "npm"
  fi
}

DETECTED_MANAGER="$(detect_package_manager)"
RUNTIME=""

if [ "$DETECTED_MANAGER" = "bun" ]; then
  if command -v bun >/dev/null 2>&1; then
    RUNTIME="bun"
  else
    echo "❌ Error: Bun was selected or autodetected as the package manager, but 'bun' is not available on PATH."
    echo "   Please install Bun (for example by using oven-sh/setup-bun in your workflow) and try again."
    exit 1
  fi
elif command -v node >/dev/null 2>&1; then
  RUNTIME="node"
elif command -v bun >/dev/null 2>&1; then
  RUNTIME="bun"
fi

if [ -z "$RUNTIME" ]; then
  echo "❌ Error: Neither Node.js nor Bun is available to run '$SCRIPT_PATH'"
  exit 1
fi

echo "🧰 Running JavaScript helper with $RUNTIME"
exec "$RUNTIME" "$SCRIPT_PATH" "$@"
