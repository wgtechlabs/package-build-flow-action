#!/bin/bash
set -e

# Generate GitHub Actions Outputs
# Process build results and generate structured outputs

echo "📊 Generating outputs..."

# Get package name
PACKAGE_NAME=$(jq -r '.name' "$PACKAGE_PATH")
echo "📦 Package: $PACKAGE_NAME"

# Generate registry URLs based on published status
REGISTRY_URLS=""

if [ "$REGISTRY" = "npm" ] || [ "$REGISTRY" = "both" ]; then
  if [ "$NPM_PUBLISHED" = "true" ]; then
    NPM_URL="${NPM_REGISTRY_URL}/${PACKAGE_NAME}"
    NPM_INSTALL="npm install ${PACKAGE_NAME}@${PACKAGE_VERSION}"
    
    if [ -z "$REGISTRY_URLS" ]; then
      REGISTRY_URLS="NPM: ${NPM_INSTALL}"
    else
      REGISTRY_URLS="${REGISTRY_URLS} | NPM: ${NPM_INSTALL}"
    fi
    
    echo "  NPM: $NPM_INSTALL"
  fi
fi

if [ "$REGISTRY" = "github" ] || [ "$REGISTRY" = "both" ]; then
  if [ "$GITHUB_PUBLISHED" = "true" ]; then
    # Determine GitHub package name
    if [[ "$PACKAGE_NAME" == @* ]]; then
      GITHUB_PACKAGE_NAME="$PACKAGE_NAME"
    elif [ -n "$PACKAGE_SCOPE" ]; then
      # Ensure scope starts with @
      if [[ "$PACKAGE_SCOPE" == @* ]]; then
        GITHUB_PACKAGE_NAME="${PACKAGE_SCOPE}/${PACKAGE_NAME}"
      else
        GITHUB_PACKAGE_NAME="@${PACKAGE_SCOPE}/${PACKAGE_NAME}"
      fi
    else
      GITHUB_PACKAGE_NAME="$PACKAGE_NAME"
    fi
    
    GITHUB_INSTALL="npm install ${GITHUB_PACKAGE_NAME}@${PACKAGE_VERSION}"
    
    if [ -z "$REGISTRY_URLS" ]; then
      REGISTRY_URLS="GitHub: ${GITHUB_INSTALL}"
    else
      REGISTRY_URLS="${REGISTRY_URLS} | GitHub: ${GITHUB_INSTALL}"
    fi
    
    echo "  GitHub: $GITHUB_INSTALL"
  fi
fi

if [ -z "$REGISTRY_URLS" ]; then
  REGISTRY_URLS="No packages published"
fi

echo ""
echo "✅ Outputs generated"
echo "  Package Version: $PACKAGE_VERSION"
echo "  Registry URLs: $REGISTRY_URLS"
echo ""

# Set GitHub Actions outputs
echo "package-version=$PACKAGE_VERSION" >> $GITHUB_OUTPUT
echo "registry-urls=$REGISTRY_URLS" >> $GITHUB_OUTPUT
