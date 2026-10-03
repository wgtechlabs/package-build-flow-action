#!/bin/bash
set -e

# Configure NPM Registries
# Handles authentication for NPM and/or GitHub Packages

echo "🔧 Configuring registries..."

NPM_AUTH_METHOD="${NPM_AUTH_METHOD:-token}"
if [ "$NPM_AUTH_METHOD" != "token" ] && [ "$NPM_AUTH_METHOD" != "oidc" ]; then
  echo "❌ Error: npm-auth-method must be 'token' or 'oidc'"
  exit 1
fi

# Validate registry input
if [ "$REGISTRY" != "npm" ] && [ "$REGISTRY" != "github" ] && [ "$REGISTRY" != "both" ]; then
  echo "❌ Error: Invalid registry value '$REGISTRY'. Must be 'npm', 'github', or 'both'"
  exit 1
fi

# Get package name from package.json
PACKAGE_NAME=$(jq -r '.name' "$PACKAGE_PATH")
echo "📦 Package name: $PACKAGE_NAME"
PACKAGE_DIR=$(cd "$(dirname "$PACKAGE_PATH")" && pwd -P)

# Read npm's effective lifecycle policy before replacing any project configuration.
if [ "$NPM_AUTH_METHOD" = "oidc" ] && [ "$REGISTRY" != "github" ]; then
  NPM_PROJECT_PREFIX=$(cd "$PACKAGE_DIR" && npm prefix)
  NPM_PUBLISH_IGNORE_SCRIPTS=$(cd "$PACKAGE_DIR" && npm --prefix "$NPM_PROJECT_PREFIX" config get ignore-scripts)
  case "$NPM_PUBLISH_IGNORE_SCRIPTS" in
    true|false) echo "npm-ignore-scripts=$NPM_PUBLISH_IGNORE_SCRIPTS" >> "$GITHUB_OUTPUT" ;;
    *) echo "❌ Error: npm ignore-scripts must resolve to true or false" >&2; exit 1 ;;
  esac
fi

# Preserve caller configuration outside the package tree until cleanup.
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REGISTRY_CONFIG_BACKUP_DIR="${REGISTRY_CONFIG_BACKUP_DIR:-$(bash "$SCRIPT_DIR/registry-config-backup.sh" backup)}"
cleanup_failed_configuration() {
  local status=$?
  if [ "$status" -ne 0 ]; then
    bash "$SCRIPT_DIR/registry-config-backup.sh" restore "$REGISTRY_CONFIG_BACKUP_DIR"
  fi
}
trap cleanup_failed_configuration EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
echo "registry-backup-dir=$REGISTRY_CONFIG_BACKUP_DIR" >> "$GITHUB_OUTPUT"

# Initialize .npmrc without following a caller's symlink.
NPMRC_FILE=".npmrc"
rm -f "$NPMRC_FILE"

# Clear or create .npmrc
(umask 077; : > "$NPMRC_FILE")

# Configure NPM registry
if [ "$REGISTRY" = "npm" ] || [ "$REGISTRY" = "both" ]; then
  echo "🔐 Configuring NPM registry..."
  
  if [ "$NPM_AUTH_METHOD" = "token" ]; then
    if [ -z "$NPM_TOKEN" ]; then
      echo "❌ Error: NPM_TOKEN is required when publishing to NPM with token authentication"
      exit 1
    fi
    NPM_REGISTRY_HOST=$(echo "$NPM_REGISTRY_URL" | sed 's|https://||' | sed 's|http://||' | sed 's|/.*||')
    echo "//${NPM_REGISTRY_HOST}/:_authToken=${NPM_TOKEN}" >> "$NPMRC_FILE"
  else
    echo "🔐 NPM trusted publishing selected; no NPM token is configured"
  fi
  
  # Only set global registry when publishing to NPM alone.
  # When REGISTRY=both, omit this line so the scoped registry for GitHub
  # Packages does not conflict with the --registry flag during npm publish.
  if [ "$REGISTRY" = "npm" ]; then
    echo "registry=${NPM_REGISTRY_URL}" >> "$NPMRC_FILE"
  fi
  
  echo "✅ NPM registry configured"
fi

# Configure GitHub Packages registry
if [ "$REGISTRY" = "github" ] || [ "$REGISTRY" = "both" ]; then
  echo "🔐 Configuring GitHub Packages..."
  
  if [ -z "$GITHUB_TOKEN" ]; then
    echo "❌ Error: GITHUB_TOKEN is required when publishing to GitHub Packages"
    exit 1
  fi
  
  # Extract registry hostname
  GITHUB_REGISTRY_HOST=$(echo "$GITHUB_REGISTRY_URL" | sed 's|https://||' | sed 's|http://||' | sed 's|/.*||')
  
  # Determine scope
  if [ -n "$PACKAGE_SCOPE" ]; then
    # Ensure scope starts with @
    if [[ "$PACKAGE_SCOPE" == @* ]]; then
      SCOPE="$PACKAGE_SCOPE"
    else
      SCOPE="@${PACKAGE_SCOPE}"
    fi
    echo "🔧 Using provided scope: $SCOPE"
  else
    # Try to extract scope from package name
    if [[ "$PACKAGE_NAME" == @* ]]; then
      SCOPE=$(echo "$PACKAGE_NAME" | cut -d'/' -f1)
      echo "📌 Using scope from package.json: $SCOPE"
    else
      # Auto-scope using repository owner
      echo "ℹ️  Package is unscoped and no scope provided"
      echo "💡 Auto-scoping enabled: Using repository owner as scope"
      if [ -z "$GITHUB_REPOSITORY_OWNER" ]; then
        echo "❌ Error: GITHUB_REPOSITORY_OWNER environment variable not set"
        exit 1
      fi
      SCOPE="@${GITHUB_REPOSITORY_OWNER}"
      echo "🔧 Scope: $SCOPE (from repository owner: ${GITHUB_REPOSITORY_OWNER})"
      echo "📌 This is required by GitHub Packages - all packages must be scoped"
    fi
  fi
  
  # Configure GitHub Packages authentication
  echo "//${GITHUB_REGISTRY_HOST}/:_authToken=${GITHUB_TOKEN}" >> "$NPMRC_FILE"
  
  # Only set scoped registry when publishing to GitHub alone.
  # When REGISTRY=both, omit this line so it does not override the
  # --registry flag during the NPM publish step for scoped packages.
  if [ "$REGISTRY" = "github" ]; then
    echo "${SCOPE}:registry=${GITHUB_REGISTRY_URL}" >> "$NPMRC_FILE"
  fi
  
  echo "✅ GitHub Packages configured (scope: $SCOPE)"
fi

# Show configuration (without tokens)
echo ""
echo "📋 Registry Configuration:"
cat "$NPMRC_FILE" | sed 's/_authToken=.*/_authToken=***/' || true
echo ""

echo "✅ Registry configuration complete"
