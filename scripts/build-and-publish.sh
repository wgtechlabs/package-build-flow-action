#!/bin/bash
set -e

# Build and Publish NPM Package
# Handles versioning, building, and publishing to registries

echo "🏗️  Building and publishing package..."

# Initialize outputs
NPM_PUBLISHED="false"
GITHUB_PUBLISHED="false"

# Get package details
PACKAGE_NAME=$(jq -r '.name' "$PACKAGE_PATH")
PACKAGE_DIR=$(dirname "$PACKAGE_PATH")

echo "📦 Package: $PACKAGE_NAME"
echo "📍 Package directory: $PACKAGE_DIR"
echo "🔖 Version: $PACKAGE_VERSION"
echo "🏷️  NPM Tag: $NPM_TAG"

# Change to package directory
cd "$PACKAGE_DIR"

# Update package.json version (no git tag)
echo "📝 Updating package.json version..."
jq --arg version "$PACKAGE_VERSION" '.version = $version' "$PACKAGE_PATH" > "${PACKAGE_PATH}.tmp"
mv "${PACKAGE_PATH}.tmp" "$PACKAGE_PATH"

echo "✅ Version updated to $PACKAGE_VERSION"

# Install dependencies
echo "📥 Installing dependencies..."
if [ -f "package-lock.json" ]; then
  npm ci
else
  npm install
fi

echo "✅ Dependencies installed"

# Run build script if defined
if [ -n "$BUILD_SCRIPT" ]; then
  if jq -e ".scripts[\"$BUILD_SCRIPT\"]" "$PACKAGE_PATH" > /dev/null 2>&1; then
    echo "🔨 Running build script: npm run $BUILD_SCRIPT"
    npm run "$BUILD_SCRIPT"
    echo "✅ Build completed"
  else
    echo "⚠️  Build script '$BUILD_SCRIPT' not found in package.json, skipping"
  fi
fi

# Run tests if defined
if jq -e '.scripts.test' "$PACKAGE_PATH" > /dev/null 2>&1; then
  echo "🧪 Running tests..."
  npm test || echo "⚠️  Tests failed but continuing..."
fi

# Check if publishing is enabled
if [ "$PUBLISH_ENABLED" != "true" ]; then
  echo "⏭️  Publishing disabled, skipping publish step"
  echo "npm-published=$NPM_PUBLISHED" >> $GITHUB_OUTPUT
  echo "github-published=$GITHUB_PUBLISHED" >> $GITHUB_OUTPUT
  exit 0
fi

# Dry run mode
if [ "$DRY_RUN" = "true" ]; then
  echo "🔍 DRY RUN MODE - No actual publishing"
  
  if [ "$REGISTRY" = "npm" ] || [ "$REGISTRY" = "both" ]; then
    echo "Would publish to NPM:"
    npm publish --dry-run --tag "$NPM_TAG" --registry "$NPM_REGISTRY_URL"
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
    
    npm publish --dry-run --tag "$NPM_TAG" --registry "$GITHUB_REGISTRY_URL"
    GITHUB_PUBLISHED="dry-run"
    
    # Restore original name if changed
    if [ "$ORIGINAL_NAME" != "$(jq -r '.name' "$PACKAGE_PATH")" ]; then
      jq --arg name "$ORIGINAL_NAME" '.name = $name' "$PACKAGE_PATH" > "${PACKAGE_PATH}.tmp"
      mv "${PACKAGE_PATH}.tmp" "$PACKAGE_PATH"
    fi
  fi
  
  echo "npm-published=$NPM_PUBLISHED" >> $GITHUB_OUTPUT
  echo "github-published=$GITHUB_PUBLISHED" >> $GITHUB_OUTPUT
  exit 0
fi

# Publish to NPM
if [ "$REGISTRY" = "npm" ] || [ "$REGISTRY" = "both" ]; then
  echo "📤 Publishing to NPM..."
  
  if npm publish --tag "$NPM_TAG" --registry "$NPM_REGISTRY_URL"; then
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
  
  if npm publish --tag "$NPM_TAG" --registry "$GITHUB_REGISTRY_URL"; then
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
echo "npm-published=$NPM_PUBLISHED" >> $GITHUB_OUTPUT
echo "github-published=$GITHUB_PUBLISHED" >> $GITHUB_OUTPUT
