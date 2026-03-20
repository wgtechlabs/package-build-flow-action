#!/bin/bash
set -e

# Build and Publish Package
# Handles versioning, building, and publishing to registries

echo "🏗️  Building and publishing package..."

# Initialize outputs
NPM_PUBLISHED="false"
GITHUB_PUBLISHED="false"

# Get package details
# Normalize PACKAGE_PATH to absolute path before cd to avoid relative path issues
if [ ! -f "$PACKAGE_PATH" ]; then
  echo "❌ Error: package.json not found at '$PACKAGE_PATH'"
  exit 1
fi
PACKAGE_PATH=$(realpath "$PACKAGE_PATH")
PACKAGE_NAME=$(jq -r '.name' "$PACKAGE_PATH")
PACKAGE_DIR=$(dirname "$PACKAGE_PATH")

echo "📦 Package: $PACKAGE_NAME"
echo "📍 Package directory: $PACKAGE_DIR"
echo "🔖 Version: $PACKAGE_VERSION"
echo "🏷️  NPM Tag: $NPM_TAG"

# Change to package directory
WORKSPACE_ROOT="$PWD"
export WORKSPACE_ROOT
cd "$PACKAGE_DIR"

has_lockfile() {
  local filename="$1"
  [ -f "$filename" ] || [ -f "$WORKSPACE_ROOT/$filename" ]
}

run_install_in_dir() {
  local target_dir="$1"
  shift
  if [ "$PWD" = "$target_dir" ]; then
    "$@"
  else
    (
      cd "$target_dir"
      "$@"
    )
  fi
}

should_install_from_workspace_root() {
  if [ "$PKG_MANAGER" != "bun" ]; then
    return 1
  fi

  if [ ! -f "$WORKSPACE_ROOT/bun.lockb" ] && [ ! -f "$WORKSPACE_ROOT/bun.lock" ]; then
    return 1
  fi

  if [ -f "$PACKAGE_DIR/bun.lockb" ] || [ -f "$PACKAGE_DIR/bun.lock" ]; then
    return 1
  fi

  return 0
}

# Ensure .npmrc is available in the package directory
# (configure-registries.sh writes it to the workspace root)
if [ "$PWD" != "$WORKSPACE_ROOT" ] && [ -f "$WORKSPACE_ROOT/.npmrc" ]; then
  cp "$WORKSPACE_ROOT/.npmrc" ".npmrc"
  echo "📋 Copied .npmrc from workspace root to package directory"
fi

# Validate and set access level
# Treat empty string as 'public' (default)
if [ -z "$ACCESS" ]; then
  ACCESS="public"
fi

if [ "$ACCESS" != "public" ] && [ "$ACCESS" != "restricted" ]; then
  echo "❌ Error: Invalid access value '$ACCESS'. Must be 'public' or 'restricted'"
  exit 1
fi

# npm only supports '--access restricted' for scoped packages (@scope/name)
if [ "$ACCESS" = "restricted" ]; then
  case "$PACKAGE_NAME" in
    @*/*)
      # Scoped package, restricted access is allowed
      echo "🔐 Package access level: $ACCESS (scoped package)"
      ;;
    *)
      echo "❌ Error: 'restricted' access is only supported for scoped packages (name must be of the form '@scope/name'). Current package name '$PACKAGE_NAME' is unscoped."
      exit 1
      ;;
  esac
else
  echo "🔐 Package access level: $ACCESS"
fi

# Update package.json version (no git tag)
echo "📝 Updating package.json version..."
jq --arg version "$PACKAGE_VERSION" '.version = $version' "$PACKAGE_PATH" > "${PACKAGE_PATH}.tmp"
mv "${PACKAGE_PATH}.tmp" "$PACKAGE_PATH"

echo "✅ Version updated to $PACKAGE_VERSION"

# Validate and resolve package manager
# First, validate the PACKAGE_MANAGER input
# Treat empty string as 'auto'
if [ -z "$PACKAGE_MANAGER" ]; then
  PACKAGE_MANAGER="auto"
fi

if [ "$PACKAGE_MANAGER" != "auto" ] && [ "$PACKAGE_MANAGER" != "npm" ] && [ "$PACKAGE_MANAGER" != "yarn" ] && [ "$PACKAGE_MANAGER" != "pnpm" ] && [ "$PACKAGE_MANAGER" != "bun" ]; then
  echo "❌ Error: Invalid package-manager value '$PACKAGE_MANAGER'. Must be 'auto', 'npm', 'yarn', 'pnpm', or 'bun'"
  exit 1
fi

# Resolve package manager based on input or auto-detection
if [ "$PACKAGE_MANAGER" = "auto" ]; then
  # Check for Bun lockfiles - bun.lockb (legacy) takes precedence for backward compatibility
  if has_lockfile "bun.lockb"; then
    PKG_MANAGER="bun"
  elif has_lockfile "bun.lock"; then
    PKG_MANAGER="bun"
  elif has_lockfile "pnpm-lock.yaml"; then
    PKG_MANAGER="pnpm"
  elif has_lockfile "yarn.lock"; then
    PKG_MANAGER="yarn"
  elif has_lockfile "package-lock.json"; then
    PKG_MANAGER="npm"
  else
    PKG_MANAGER="npm"
  fi
else
  PKG_MANAGER="$PACKAGE_MANAGER"
fi

# Verify the selected package manager is available
if [ "$PKG_MANAGER" = "bun" ]; then
  if ! command -v bun >/dev/null 2>&1; then
    echo "❌ Error: Bun is selected but 'bun' command is not found. Please install Bun using 'oven-sh/setup-bun@v2' or similar action."
    exit 1
  fi
elif [ "$PKG_MANAGER" = "pnpm" ]; then
  if ! command -v pnpm >/dev/null 2>&1; then
    echo "❌ Error: pnpm is selected but 'pnpm' command is not found. Please install pnpm using 'pnpm/action-setup@v2' or similar action."
    exit 1
  fi
elif [ "$PKG_MANAGER" = "yarn" ]; then
  if ! command -v yarn >/dev/null 2>&1; then
    echo "❌ Error: Yarn is selected but 'yarn' command is not found. Please install Yarn or use 'actions/setup-node' with appropriate configuration."
    exit 1
  fi
fi

echo "📦 Using package manager: $PKG_MANAGER"

# Install dependencies
echo "📥 Installing dependencies..."
INSTALL_DIR="$PACKAGE_DIR"
if should_install_from_workspace_root; then
  INSTALL_DIR="$WORKSPACE_ROOT"
  echo "📍 Running Bun install from workspace root: $INSTALL_DIR"
fi

if [ "$PKG_MANAGER" = "bun" ]; then
  run_install_in_dir "$INSTALL_DIR" bun install --frozen-lockfile
elif [ "$PKG_MANAGER" = "pnpm" ]; then
  run_install_in_dir "$INSTALL_DIR" pnpm install --frozen-lockfile
elif [ "$PKG_MANAGER" = "yarn" ]; then
  # Yarn v1 uses --frozen-lockfile, Yarn v2+ uses --immutable
  # Check major version number
  YARN_MAJOR_VERSION=$(yarn --version | cut -d. -f1)
  if [ "$YARN_MAJOR_VERSION" -ge 2 ]; then
    run_install_in_dir "$INSTALL_DIR" yarn install --immutable
  else
    run_install_in_dir "$INSTALL_DIR" yarn install --frozen-lockfile
  fi
elif has_lockfile "package-lock.json"; then
  run_install_in_dir "$INSTALL_DIR" npm ci
else
  run_install_in_dir "$INSTALL_DIR" npm install
fi

echo "✅ Dependencies installed"

# Run build script if defined
if [ -n "$BUILD_SCRIPT" ]; then
  if jq -e ".scripts[\"$BUILD_SCRIPT\"]" "$PACKAGE_PATH" > /dev/null 2>&1; then
    echo "🔨 Running build script: $PKG_MANAGER run $BUILD_SCRIPT"
    "$PKG_MANAGER" run "$BUILD_SCRIPT"
    echo "✅ Build completed"
  else
    echo "⚠️  Build script '$BUILD_SCRIPT' not found in package.json, skipping"
  fi
fi

# Run tests if defined
if jq -e '.scripts.test' "$PACKAGE_PATH" > /dev/null 2>&1; then
  echo "🧪 Running tests..."
  # Use 'run test' for consistent behavior across npm and Bun
  # This ensures we run the package.json script, not Bun's built-in test runner
  "$PKG_MANAGER" run test || echo "⚠️  Tests failed but continuing..."
fi

# Resolve workspace protocol dependencies before publishing
# This converts workspace:* references to actual semver versions
WORKSPACE_BACKUP="${PACKAGE_PATH}.workspace-backup"
WORKSPACE_BACKUP_EXISTS=false

# Setup trap to restore workspace backup on exit
cleanup_workspace_backup() {
  if [ "$WORKSPACE_BACKUP_EXISTS" = true ] && [ -f "$WORKSPACE_BACKUP" ]; then
    if mv "$WORKSPACE_BACKUP" "$PACKAGE_PATH" 2>/dev/null; then
      echo "📝 Restored original package.json with workspace protocol" >&2
      # Clean up backup file only after successful restore
      rm -f "$WORKSPACE_BACKUP" 2>/dev/null || true
      WORKSPACE_BACKUP_EXISTS=false
    else
      echo "⚠️  Failed to restore original package.json; backup retained at '$WORKSPACE_BACKUP'" >&2
    fi
  fi
}
trap cleanup_workspace_backup EXIT INT TERM

# Check if DISCOVERED_PACKAGES is available and contains packages (using jq for robust check)
if [ -n "$DISCOVERED_PACKAGES" ] && echo "$DISCOVERED_PACKAGES" | jq -e 'type=="array" and length>0' >/dev/null 2>&1; then
  echo ""
  echo "🔄 Checking for workspace protocol dependencies..."
  
  # Create backup of package.json before resolution
  cp "$PACKAGE_PATH" "$WORKSPACE_BACKUP"
  WORKSPACE_BACKUP_EXISTS=true
  
  # Run workspace protocol resolution
  if bash "$ACTION_PATH/scripts/run-js-file.sh" "$ACTION_PATH/scripts/resolve-workspace-protocol.js"; then
    echo "✅ Workspace protocol resolution completed"
  else
    echo "⚠️  Warning: Workspace protocol resolution failed, continuing with original package.json"
    # Restore backup if resolution failed
    if [ -f "$WORKSPACE_BACKUP" ]; then
      mv "$WORKSPACE_BACKUP" "$PACKAGE_PATH"
      WORKSPACE_BACKUP_EXISTS=false
    fi
  fi
  echo ""
fi

# Bot detection override: force dry-run when bot actor detected
if [ "${BOT_DRY_RUN:-false}" = "true" ]; then
  echo "🤖 Bot actor detected — forcing validation-only mode (publish skipped)"
  DRY_RUN="true"
fi

# Publish package using the selected package manager
publish_package() {
  local registry_url="$1"
  local dry_run="$2"

  local publish_cmd=()
  if [ "$PKG_MANAGER" = "bun" ]; then
    publish_cmd=(bun publish --tag "$NPM_TAG" --registry "$registry_url")
  else
    publish_cmd=(npm publish --tag "$NPM_TAG" --registry "$registry_url")
  fi

  if [ "$dry_run" = "true" ]; then
    publish_cmd+=(--dry-run)
  fi

  if [[ "$PACKAGE_NAME" == @*/* ]]; then
    publish_cmd+=(--access "$ACCESS")
  fi

  "${publish_cmd[@]}"
}

# Check if publishing is enabled
if [ "$PUBLISH_ENABLED" != "true" ]; then
  echo "⏭️  Publishing disabled, skipping publish step"
  
  echo "npm-published=$NPM_PUBLISHED" >> "$GITHUB_OUTPUT"
  echo "github-published=$GITHUB_PUBLISHED" >> "$GITHUB_OUTPUT"
  exit 0
fi

# Dry run mode
if [ "$DRY_RUN" = "true" ]; then
  echo "🔍 DRY RUN MODE - No actual publishing"
  
  if [ "$REGISTRY" = "npm" ] || [ "$REGISTRY" = "both" ]; then
    echo "Would publish to NPM:"
    publish_package "$NPM_REGISTRY_URL" "true"
    NPM_PUBLISHED="dry-run"
  fi
  
  if [ "$REGISTRY" = "github" ] || [ "$REGISTRY" = "both" ]; then
    echo "Would publish to GitHub Packages:"
    
    # Ensure package is scoped for GitHub Packages
    ORIGINAL_NAME=$(jq -r '.name' "$PACKAGE_PATH")
    if [[ "$ORIGINAL_NAME" != @* ]]; then
      # Determine scope
      if [ -n "$PACKAGE_SCOPE" ]; then
        # Use provided scope
        if [[ "$PACKAGE_SCOPE" == @* ]]; then
          SCOPED_NAME="${PACKAGE_SCOPE}/${ORIGINAL_NAME}"
        else
          SCOPED_NAME="@${PACKAGE_SCOPE}/${ORIGINAL_NAME}"
        fi
      else
        # Auto-scope using repository owner
        if [ -z "$GITHUB_REPOSITORY_OWNER" ]; then
          echo "❌ Error: GITHUB_REPOSITORY_OWNER environment variable not set"
          exit 1
        fi
        SCOPED_NAME="@${GITHUB_REPOSITORY_OWNER}/${ORIGINAL_NAME}"
        echo "💡 Auto-scoping: ${ORIGINAL_NAME} → ${SCOPED_NAME}"
      fi
      jq --arg name "$SCOPED_NAME" '.name = $name' "$PACKAGE_PATH" > "${PACKAGE_PATH}.tmp"
      mv "${PACKAGE_PATH}.tmp" "$PACKAGE_PATH"
      echo "📝 Scoped package name: $SCOPED_NAME"
    fi
    
    publish_package "$GITHUB_REGISTRY_URL" "true"
    GITHUB_PUBLISHED="dry-run"
    
    # Restore original name if changed
    if [ "$ORIGINAL_NAME" != "$(jq -r '.name' "$PACKAGE_PATH")" ]; then
      jq --arg name "$ORIGINAL_NAME" '.name = $name' "$PACKAGE_PATH" > "${PACKAGE_PATH}.tmp"
      mv "${PACKAGE_PATH}.tmp" "$PACKAGE_PATH"
    fi
  fi
  
  echo "npm-published=$NPM_PUBLISHED" >> "$GITHUB_OUTPUT"
  echo "github-published=$GITHUB_PUBLISHED" >> "$GITHUB_OUTPUT"
  exit 0
fi

# Publish to NPM
if [ "$REGISTRY" = "npm" ] || [ "$REGISTRY" = "both" ]; then
  echo "📤 Publishing to NPM..."
  
  if publish_package "$NPM_REGISTRY_URL" "false"; then
    NPM_PUBLISHED="true"
    echo "✅ Published to NPM: $PACKAGE_NAME@$PACKAGE_VERSION (tag: $NPM_TAG)"
  else
    echo "❌ Failed to publish to NPM"
    NPM_PUBLISHED="false"
  fi
fi

# Publish to GitHub Packages
if [ "$REGISTRY" = "github" ] || [ "$REGISTRY" = "both" ]; then
  echo "📤 Publishing to GitHub Packages..."
  
  # Ensure package is scoped for GitHub Packages
  ORIGINAL_NAME=$(jq -r '.name' "$PACKAGE_PATH")
  NEEDS_RESTORE=false
  
  if [[ "$ORIGINAL_NAME" != @* ]]; then
    # Determine scope
    if [ -n "$PACKAGE_SCOPE" ]; then
      # Use provided scope
      if [[ "$PACKAGE_SCOPE" == @* ]]; then
        SCOPED_NAME="${PACKAGE_SCOPE}/${ORIGINAL_NAME}"
      else
        SCOPED_NAME="@${PACKAGE_SCOPE}/${ORIGINAL_NAME}"
      fi
    else
      # Auto-scope using repository owner
      if [ -z "$GITHUB_REPOSITORY_OWNER" ]; then
        echo "❌ Error: GITHUB_REPOSITORY_OWNER environment variable not set"
        exit 1
      fi
      SCOPED_NAME="@${GITHUB_REPOSITORY_OWNER}/${ORIGINAL_NAME}"
      echo "💡 Auto-scoping: ${ORIGINAL_NAME} → ${SCOPED_NAME}"
    fi
    jq --arg name "$SCOPED_NAME" '.name = $name' "$PACKAGE_PATH" > "${PACKAGE_PATH}.tmp"
    mv "${PACKAGE_PATH}.tmp" "$PACKAGE_PATH"
    echo "📝 Scoped package name for GitHub: $SCOPED_NAME"
    NEEDS_RESTORE=true
  fi
  
  if publish_package "$GITHUB_REGISTRY_URL" "false"; then
    GITHUB_PUBLISHED="true"
    PUBLISHED_NAME=$(jq -r '.name' "$PACKAGE_PATH")
    echo "✅ Published to GitHub Packages: $PUBLISHED_NAME@$PACKAGE_VERSION (tag: $NPM_TAG)"
  else
    echo "❌ Failed to publish to GitHub Packages"
    GITHUB_PUBLISHED="false"
  fi
  
  # Restore original name if changed
  if [ "$NEEDS_RESTORE" = true ]; then
    jq --arg name "$ORIGINAL_NAME" '.name = $name' "$PACKAGE_PATH" > "${PACKAGE_PATH}.tmp"
    mv "${PACKAGE_PATH}.tmp" "$PACKAGE_PATH"
    echo "📝 Restored original package name"
  fi
fi

echo ""
echo "✅ Build and publish complete"
echo "  NPM Published: $NPM_PUBLISHED"
echo "  GitHub Published: $GITHUB_PUBLISHED"
echo ""

# Set outputs
echo "npm-published=$NPM_PUBLISHED" >> "$GITHUB_OUTPUT"
echo "github-published=$GITHUB_PUBLISHED" >> "$GITHUB_OUTPUT"

# Note: Workspace backup restoration happens automatically via EXIT trap
