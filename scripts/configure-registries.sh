#!/bin/bash
set -e

# Configure NPM Registries
# Handles authentication for NPM and/or GitHub Packages

echo "🔧 Configuring registries..."

# Validate registry input
if [ "$REGISTRY" != "npm" ] && [ "$REGISTRY" != "github" ] && [ "$REGISTRY" != "both" ]; then
  echo "❌ Error: Invalid registry value '$REGISTRY'. Must be 'npm', 'github', or 'both'"
  exit 1
fi

# Get package name from package.json
PACKAGE_NAME=$(jq -r '.name' "$PACKAGE_PATH")
echo "📦 Package name: $PACKAGE_NAME"

# Initialize .npmrc
NPMRC_FILE=".npmrc"
if [ -f "$NPMRC_FILE" ]; then
  echo "⚠️  Backing up existing .npmrc"
  cp "$NPMRC_FILE" "${NPMRC_FILE}.backup"
fi

# Clear or create .npmrc
> "$NPMRC_FILE"

# Configure NPM registry
if [ "$REGISTRY" = "npm" ] || [ "$REGISTRY" = "both" ]; then
  echo "🔐 Configuring NPM registry..."
  
  if [ -z "$NPM_TOKEN" ]; then
    echo "❌ Error: NPM_TOKEN is required when publishing to NPM"
    exit 1
  fi
  
  # Extract registry hostname
  NPM_REGISTRY_HOST=$(echo "$NPM_REGISTRY_URL" | sed 's|https://||' | sed 's|http://||' | sed 's|/.*||')
  
  # Configure NPM authentication
  echo "//${NPM_REGISTRY_HOST}/:_authToken=${NPM_TOKEN}" >> "$NPMRC_FILE"
  echo "registry=${NPM_REGISTRY_URL}" >> "$NPMRC_FILE"
  
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
    SCOPE="$PACKAGE_SCOPE"
  else
    # Try to extract scope from package name
    if [[ "$PACKAGE_NAME" == @* ]]; then
      SCOPE=$(echo "$PACKAGE_NAME" | cut -d'/' -f1)
    else
      echo "❌ Error: PACKAGE_SCOPE is required for GitHub Packages when package name is not scoped"
      exit 1
    fi
  fi
  
  # Configure GitHub Packages authentication
  echo "//${GITHUB_REGISTRY_HOST}/:_authToken=${GITHUB_TOKEN}" >> "$NPMRC_FILE"
  echo "${SCOPE}:registry=${GITHUB_REGISTRY_URL}" >> "$NPMRC_FILE"
  
  echo "✅ GitHub Packages configured (scope: $SCOPE)"
fi

# Show configuration (without tokens)
echo ""
echo "📋 Registry Configuration:"
cat "$NPMRC_FILE" | sed 's/_authToken=.*/_authToken=***/' || true
echo ""

echo "✅ Registry configuration complete"
