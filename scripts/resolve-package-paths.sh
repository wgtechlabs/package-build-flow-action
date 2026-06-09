#!/bin/bash
set -e

echo "🧭 Resolving package paths..."

WORKSPACE_ROOT="${GITHUB_WORKSPACE:-$PWD}"
PACKAGE_PATH_INPUT="${PACKAGE_PATH:-./package.json}"
PACKAGE_PATHS_INPUT="${PACKAGE_PATHS:-}"
CHECKOUT_REQUIRED="false"

resolve_path() {
  local input_path="$1"

  if [ -z "$input_path" ]; then
    return 0
  fi

  if [[ "$input_path" = /* ]]; then
    printf '%s\n' "$input_path"
  else
    input_path="${input_path#./}"
    printf '%s/%s\n' "$WORKSPACE_ROOT" "$input_path"
  fi
}

RESOLVED_PACKAGE_PATH="$(resolve_path "$PACKAGE_PATH_INPUT")"

if [[ "$RESOLVED_PACKAGE_PATH" == "$WORKSPACE_ROOT"/* ]] && [ ! -f "$RESOLVED_PACKAGE_PATH" ]; then
  CHECKOUT_REQUIRED="true"
fi

RESOLVED_PACKAGE_PATHS=""

if [ -n "$PACKAGE_PATHS_INPUT" ]; then
  declare -a RESOLVED_PATH_ARRAY=()

  IFS=',' read -ra PACKAGE_PATH_ARRAY <<< "$PACKAGE_PATHS_INPUT"
  for raw_path in "${PACKAGE_PATH_ARRAY[@]}"; do
    trimmed_path="${raw_path#"${raw_path%%[![:space:]]*}"}"
    trimmed_path="${trimmed_path%"${trimmed_path##*[![:space:]]}"}"

    if [ -z "$trimmed_path" ]; then
      continue
    fi

    resolved_path="$(resolve_path "$trimmed_path")"
    RESOLVED_PATH_ARRAY+=("$resolved_path")

    if [[ "$resolved_path" == "$WORKSPACE_ROOT"/* ]] && [ ! -f "$resolved_path" ]; then
      CHECKOUT_REQUIRED="true"
    fi
  done

  if [ "${#RESOLVED_PATH_ARRAY[@]}" -gt 0 ]; then
    RESOLVED_PACKAGE_PATHS="$(IFS=,; echo "${RESOLVED_PATH_ARRAY[*]}")"
  fi
fi

echo "📍 Workspace root: $WORKSPACE_ROOT"
echo "📄 Resolved package-path: $RESOLVED_PACKAGE_PATH"

if [ -n "$RESOLVED_PACKAGE_PATHS" ]; then
  echo "📚 Resolved package-paths: $RESOLVED_PACKAGE_PATHS"
fi

if [ "$CHECKOUT_REQUIRED" = "true" ]; then
  echo "📥 Repository contents are not present yet; checkout will be requested"
fi

echo "workspace-root=$WORKSPACE_ROOT" >> "$GITHUB_OUTPUT"
echo "package-path=$RESOLVED_PACKAGE_PATH" >> "$GITHUB_OUTPUT"
echo "package-paths=$RESOLVED_PACKAGE_PATHS" >> "$GITHUB_OUTPUT"
echo "checkout-required=$CHECKOUT_REQUIRED" >> "$GITHUB_OUTPUT"
