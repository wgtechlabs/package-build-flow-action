#!/bin/bash
set -e

# Generate GitHub Actions Outputs
# Process build results and generate structured outputs

echo "📊 Generating outputs..."

# Check if in monorepo mode
if [ "$MONOREPO_MODE" = "true" ]; then
  echo "🎯 Monorepo mode - generating aggregated outputs"
  
  # Validate JSON inputs
  if ! echo "$BUILD_RESULTS_JSON" | jq -e . >/dev/null 2>&1; then
    echo "⚠️  Warning: BUILD_RESULTS_JSON is invalid or empty, using defaults"
    BUILD_RESULTS_JSON='[]'
  fi
  
  if ! echo "$CHANGED_PACKAGES_JSON" | jq -e . >/dev/null 2>&1; then
    echo "⚠️  Warning: CHANGED_PACKAGES_JSON is invalid or empty, using defaults"
    CHANGED_PACKAGES_JSON='[]'
  fi
  
  # Parse BUILD_RESULTS_JSON to extract package information
  PACKAGES_PUBLISHED=$(echo "$BUILD_RESULTS_JSON" | jq -r '[.[] | select(.result == "success") | .name] | join(",")')
  PACKAGES_FAILED=$(echo "$BUILD_RESULTS_JSON" | jq -r '[.[] | select(.result == "failed") | .name] | join(",")')
  TOTAL_PACKAGES=$(echo "$BUILD_RESULTS_JSON" | jq '. | length')
  CHANGED_PACKAGES_COUNT=$(echo "$CHANGED_PACKAGES_JSON" | jq '. | length')
  
  echo "  Total packages: $TOTAL_PACKAGES"
  echo "  Changed packages: $CHANGED_PACKAGES_COUNT"
  echo "  Successfully published: $PACKAGES_PUBLISHED"
  
  if [ -n "$PACKAGES_FAILED" ]; then
    echo "  Failed packages: $PACKAGES_FAILED"
  fi
  
  # Set GitHub Actions outputs
  echo "packages-published=$PACKAGES_PUBLISHED" >> "$GITHUB_OUTPUT"
  echo "packages-failed=$PACKAGES_FAILED" >> "$GITHUB_OUTPUT"
  echo "total-packages=$TOTAL_PACKAGES" >> "$GITHUB_OUTPUT"
  echo "changed-packages-count=$CHANGED_PACKAGES_COUNT" >> "$GITHUB_OUTPUT"
  
  echo ""
  echo "✅ Monorepo outputs generated"
  
else
  # Single package mode - existing behavior
  echo "📦 Single package mode"
  
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
        # Auto-scope using repository owner
        if [ -z "$GITHUB_REPOSITORY_OWNER" ]; then
          echo "⚠️  Warning: GITHUB_REPOSITORY_OWNER not set, using unscoped name"
          GITHUB_PACKAGE_NAME="$PACKAGE_NAME"
        else
          GITHUB_PACKAGE_NAME="@${GITHUB_REPOSITORY_OWNER}/${PACKAGE_NAME}"
        fi
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
  echo "package-version=$PACKAGE_VERSION" >> "$GITHUB_OUTPUT"
  echo "registry-urls=$REGISTRY_URLS" >> "$GITHUB_OUTPUT"
fi
