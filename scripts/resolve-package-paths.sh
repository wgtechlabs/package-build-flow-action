#!/bin/bash
set -e

echo "🧭 Resolving package paths..."

WORKSPACE_ROOT="${GITHUB_WORKSPACE:-$PWD}"
PACKAGE_PATH_INPUT="${PACKAGE_PATH:-./package.json}"
PACKAGE_PATHS_INPUT="${PACKAGE_PATHS:-}"
CHECKOUT_REQUIRED="false"

normalize_path() {
  local absolute_path="$1"
  local -a path_stack=()
  local IFS='/'
  read -ra path_parts <<< "$absolute_path"

  for part in "${path_parts[@]}"; do
    case "$part" in
      ''|'.')
        continue
        ;;
      '..')
        if [ "${#path_stack[@]}" -gt 0 ]; then
          unset 'path_stack[${#path_stack[@]}-1]'
        fi
        ;;
      *)
        path_stack+=("$part")
        ;;
    esac
  done

  printf '/%s\n' "$(IFS=/; echo "${path_stack[*]}")"
}

resolve_path() {
  local input_path="$1"
  local candidate_path

  if [ -z "$input_path" ]; then
    return 0
  fi

  if [[ "$input_path" = /* ]]; then
    candidate_path="$input_path"
  else
    input_path="${input_path#./}"
    candidate_path="$WORKSPACE_ROOT/$input_path"
  fi

  normalize_path "$candidate_path"
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
