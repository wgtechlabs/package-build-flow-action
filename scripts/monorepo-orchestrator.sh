#!/bin/bash
set -e

# Monorepo Orchestrator
# Loops over multiple package paths and runs detect → build → publish for each

echo "🎯 Monorepo mode enabled"
echo "===================="
echo ""

# Check if package-paths is provided
if [ -z "$PACKAGE_PATHS" ]; then
  echo "❌ Error: package-paths input is required in monorepo mode"
  exit 1
fi

# Parse comma-separated package paths into an array
IFS=',' read -ra PACKAGE_ARRAY <<< "$PACKAGE_PATHS"

# Initialize results array
BUILD_RESULTS="[]"

# Track success/failure
TOTAL_PACKAGES=${#PACKAGE_ARRAY[@]}
SUCCESSFUL_PACKAGES=0
FAILED_PACKAGES=0

echo "📦 Found $TOTAL_PACKAGES package(s) to process"
echo ""

# Process each package
for i in "${!PACKAGE_ARRAY[@]}"; do
  PACKAGE_PATH="${PACKAGE_ARRAY[$i]}"
  # Trim whitespace
  PACKAGE_PATH=$(echo "$PACKAGE_PATH" | xargs)
  
  PACKAGE_NUM=$((i + 1))
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📦 Processing package $PACKAGE_NUM/$TOTAL_PACKAGES: $PACKAGE_PATH"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  
  # Check if package.json exists
  if [ ! -f "$PACKAGE_PATH" ]; then
    echo "❌ Error: package.json not found at '$PACKAGE_PATH'"
    PACKAGE_NAME="unknown"
    PACKAGE_VERSION="unknown"
    RESULT="error"
    ERROR_MESSAGE="package.json not found"
    FAILED_PACKAGES=$((FAILED_PACKAGES + 1))
    
    # Add to results
    BUILD_RESULTS=$(echo "$BUILD_RESULTS" | jq --arg name "$PACKAGE_NAME" \
      --arg version "$PACKAGE_VERSION" \
      --arg result "$RESULT" \
      --arg error "$ERROR_MESSAGE" \
      '. += [{"name": $name, "version": $version, "result": $result, "error": $error}]')
    echo ""
    continue
  fi
  
  PACKAGE_NAME=$(jq -r '.name' "$PACKAGE_PATH")
  echo "📋 Package name: $PACKAGE_NAME"
  
  # Set environment for this package
  export PACKAGE_PATH
  
  # Create a temporary output file for this package's steps
  TEMP_OUTPUT=$(mktemp)
  
  # Step 1: Detect flow
  echo "🔍 Step 1/4: Detecting build flow..."
  if bash "$ACTION_PATH/scripts/detect-package-flow.sh" > "$TEMP_OUTPUT" 2>&1; then
    cat "$TEMP_OUTPUT"
    
    # Parse outputs from the detect script
    # The script writes to GITHUB_OUTPUT, but we need to capture those values
    # We'll re-run the detection logic inline to get the values
    PACKAGE_VERSION=""
    NPM_TAG=""
    
    # Re-parse to get version and tag
    if [ -f "$GITHUB_OUTPUT" ]; then
      PACKAGE_VERSION=$(grep "^version=" "$GITHUB_OUTPUT" | tail -1 | cut -d= -f2-)
      NPM_TAG=$(grep "^npm-tag=" "$GITHUB_OUTPUT" | tail -1 | cut -d= -f2-)
    fi
    
    # If not found in GITHUB_OUTPUT, parse from the temp output
    if [ -z "$PACKAGE_VERSION" ]; then
      PACKAGE_VERSION=$(grep "Package Version:" "$TEMP_OUTPUT" | tail -1 | awk '{print $NF}')
    fi
    if [ -z "$NPM_TAG" ]; then
      NPM_TAG=$(grep "NPM Tag:" "$TEMP_OUTPUT" | tail -1 | awk '{print $NF}')
    fi
    
    echo "✅ Flow detection completed"
  else
    cat "$TEMP_OUTPUT"
    echo "❌ Flow detection failed"
    PACKAGE_VERSION="unknown"
    RESULT="error"
    ERROR_MESSAGE="Flow detection failed"
    FAILED_PACKAGES=$((FAILED_PACKAGES + 1))
    
    BUILD_RESULTS=$(echo "$BUILD_RESULTS" | jq --arg name "$PACKAGE_NAME" \
      --arg version "$PACKAGE_VERSION" \
      --arg result "$RESULT" \
      --arg error "$ERROR_MESSAGE" \
      '. += [{"name": $name, "version": $version, "result": $result, "error": $error}]')
    rm -f "$TEMP_OUTPUT"
    echo ""
    continue
  fi
  
  # Step 2: Configure registries
  echo ""
  echo "⚙️  Step 2/4: Configuring registries..."
  if bash "$ACTION_PATH/scripts/configure-registries.sh" > "$TEMP_OUTPUT" 2>&1; then
    cat "$TEMP_OUTPUT"
    echo "✅ Registry configuration completed"
  else
    cat "$TEMP_OUTPUT"
    echo "❌ Registry configuration failed"
    RESULT="error"
    ERROR_MESSAGE="Registry configuration failed"
    FAILED_PACKAGES=$((FAILED_PACKAGES + 1))
    
    BUILD_RESULTS=$(echo "$BUILD_RESULTS" | jq --arg name "$PACKAGE_NAME" \
      --arg version "$PACKAGE_VERSION" \
      --arg result "$RESULT" \
      --arg error "$ERROR_MESSAGE" \
      '. += [{"name": $name, "version": $version, "result": $result, "error": $error}]')
    rm -f "$TEMP_OUTPUT"
    echo ""
    continue
  fi
  
  # Step 3: Build and publish
  echo ""
  echo "🏗️  Step 3/4: Building and publishing..."
  export PACKAGE_VERSION
  export NPM_TAG
  
  if bash "$ACTION_PATH/scripts/build-and-publish.sh" > "$TEMP_OUTPUT" 2>&1; then
    cat "$TEMP_OUTPUT"
    echo "✅ Build and publish completed"
    RESULT="success"
    SUCCESSFUL_PACKAGES=$((SUCCESSFUL_PACKAGES + 1))
  else
    cat "$TEMP_OUTPUT"
    echo "❌ Build and publish failed (but continuing with remaining packages)"
    RESULT="failed"
    ERROR_MESSAGE="Build or publish failed"
    FAILED_PACKAGES=$((FAILED_PACKAGES + 1))
  fi
  
  # Step 4: Run audit if enabled
  echo ""
  if [ "$AUDIT_ENABLED" = "true" ]; then
    echo "🔒 Step 4/4: Running security audit..."
    if node "$ACTION_PATH/scripts/audit-package.js" > "$TEMP_OUTPUT" 2>&1; then
      cat "$TEMP_OUTPUT"
      echo "✅ Security audit completed"
    else
      cat "$TEMP_OUTPUT"
      echo "⚠️  Security audit failed (but continuing)"
      # Don't mark as failed if only audit fails
    fi
  else
    echo "⏭️  Step 4/4: Security audit disabled"
  fi
  
  # Add to results
  if [ "$RESULT" = "success" ]; then
    BUILD_RESULTS=$(echo "$BUILD_RESULTS" | jq --arg name "$PACKAGE_NAME" \
      --arg version "$PACKAGE_VERSION" \
      --arg result "$RESULT" \
      '. += [{"name": $name, "version": $version, "result": $result}]')
  else
    BUILD_RESULTS=$(echo "$BUILD_RESULTS" | jq --arg name "$PACKAGE_NAME" \
      --arg version "$PACKAGE_VERSION" \
      --arg result "$RESULT" \
      --arg error "${ERROR_MESSAGE:-Unknown error}" \
      '. += [{"name": $name, "version": $version, "result": $result, "error": $error}]')
  fi
  
  rm -f "$TEMP_OUTPUT"
  echo ""
done

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 Monorepo Build Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Total packages: $TOTAL_PACKAGES"
echo "✅ Successful: $SUCCESSFUL_PACKAGES"
echo "❌ Failed: $FAILED_PACKAGES"
echo ""
echo "Results:"
echo "$BUILD_RESULTS" | jq '.'
echo ""

# Set outputs
echo "build-results=$BUILD_RESULTS" >> "$GITHUB_OUTPUT"

# Exit with error if any package failed
if [ "$FAILED_PACKAGES" -gt 0 ]; then
  echo "❌ Monorepo build completed with $FAILED_PACKAGES failure(s)"
  exit 1
else
  echo "✅ All packages processed successfully"
  exit 0
fi
