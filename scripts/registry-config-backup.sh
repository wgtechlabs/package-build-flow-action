#!/bin/bash
set -e

# Keep original npm configuration outside every package that may be packed.
restore_configs() {
  local state="$1" target_file target index
  [ -d "$state" ] || return 0
  for target_file in "$state"/target-*; do
    [ -f "$target_file" ] || continue
    target=$(cat "$target_file")
    index=${target_file##*-}
    rm -f "$target"
    if [ -e "$state/original-$index" ] || [ -L "$state/original-$index" ]; then
      cp -Pp "$state/original-$index" "$target"
    fi
  done
  rm -rf "$state"
}

case "${1:-}" in
  backup)
    workspace=$(pwd -P)
    package_dir=$(cd "$(dirname "$PACKAGE_PATH")" && pwd -P)
    state=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/package-build-flow-npmrc.XXXXXX")
    state=$(cd "$state" && pwd -P)
    for directory in "$workspace" "$package_dir"; do
      case "$state/" in
        "$directory/"*)
          rmdir "$state"
          echo "Registry backup directory must be outside the workspace and package" >&2
          exit 1
          ;;
      esac
    done
    trap 'status=$?; if [ "$status" -ne 0 ]; then restore_configs "$state"; fi' EXIT
    index=0
    for directory in "$workspace" "$package_dir"; do
      [ "$index" = 1 ] && [ "$directory" = "$workspace" ] && continue
      target="$directory/.npmrc"
      if [ -e "$target" ] || [ -L "$target" ]; then
        cp -Pp "$target" "$state/original-$index"
      fi
      printf '%s' "$target" > "$state/target-$index"
      index=$((index + 1))
    done
    printf '%s\n' "$state"
    ;;
  restore)
    restore_configs "${2:?Registry backup directory is required}"
    ;;
  *)
    echo "Usage: registry-config-backup.sh backup|restore <directory>" >&2
    exit 1
    ;;
esac
