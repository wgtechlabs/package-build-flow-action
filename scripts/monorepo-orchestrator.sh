#!/bin/bash
set -e

# Monorepo Orchestrator
# Loops over multiple package paths and runs detect → build → publish for each

echo "🎯 Monorepo mode enabled"
echo "===================="
echo ""

# Priority logic for determining package list:
# 1. If package-paths is explicitly provided → use it
# 2. Else if workspace-detection is enabled → auto-discover from root package.json
# 3. Else → error

if [ -n "$PACKAGE_PATHS" ]; then
  echo "📋 Using explicitly provided package-paths"
  echo ""
  
  # Parse comma-separated package paths into an array
  IFS=',' read -ra PACKAGE_ARRAY <<< "$PACKAGE_PATHS"
  
  # Filter out empty entries after trimming
  FILTERED_PACKAGES=()
  for pkg in "${PACKAGE_ARRAY[@]}"; do
    # Trim whitespace
    pkg=$(echo "$pkg" | xargs)
    # Only add non-empty paths
    if [ -n "$pkg" ]; then
      FILTERED_PACKAGES+=("$pkg")
    fi
  done
  PACKAGE_ARRAY=("${FILTERED_PACKAGES[@]}")
  
  TOTAL_PACKAGES=${#PACKAGE_ARRAY[@]}
  
  if [ "$TOTAL_PACKAGES" -eq 0 ]; then
    echo "❌ Error: No valid package paths provided after filtering"
    exit 1
  fi
  
  # Set empty outputs for discovery (not used when package-paths is explicit)
  echo "discovered-packages=[]" >> "$GITHUB_OUTPUT"
  echo "package-count=0" >> "$GITHUB_OUTPUT"
  
  # Initialize discovered packages as empty when using explicit package-paths
  DISCOVERED_PACKAGES="[]"
  
elif [ "$WORKSPACE_DETECTION" = "true" ]; then
  echo "🔍 Auto-discovering packages from workspace configuration"
  echo ""
  
  # Run workspace discovery script
  DISCOVERY_OUTPUT=$(mktemp)
  DISCOVERY_OUTPUTS=$(mktemp)
  
  # Save current GITHUB_OUTPUT location
  ORIGINAL_OUTPUT="$GITHUB_OUTPUT"
  # Use temporary file for discovery outputs
  export GITHUB_OUTPUT="$DISCOVERY_OUTPUTS"
  
  if bash "$ACTION_PATH/scripts/discover-workspaces.sh" > "$DISCOVERY_OUTPUT" 2>&1; then
    cat "$DISCOVERY_OUTPUT"
    
    # Read outputs from temporary file
    if [ -f "$DISCOVERY_OUTPUTS" ]; then
      DISCOVERED_PACKAGES=$(grep "^discovered-packages=" "$DISCOVERY_OUTPUTS" | tail -1 | cut -d= -f2-)
      PKG_COUNT=$(grep "^package-count=" "$DISCOVERY_OUTPUTS" | tail -1 | cut -d= -f2-)
      
      # Copy discovery outputs to the original GITHUB_OUTPUT
      export GITHUB_OUTPUT="$ORIGINAL_OUTPUT"
      echo "discovered-packages=$DISCOVERED_PACKAGES" >> "$GITHUB_OUTPUT"
      echo "package-count=$PKG_COUNT" >> "$GITHUB_OUTPUT"
      
      # Extract comma-separated package paths from the discovered packages JSON (simplified)
      PACKAGE_PATHS=$(echo "$DISCOVERED_PACKAGES" | jq -r '[.[].path] | join(",")')
      
      if [ -z "$PACKAGE_PATHS" ] || [ "$PACKAGE_PATHS" = "null" ]; then
        echo "❌ Error: No packages discovered from workspace configuration"
        rm -f "$DISCOVERY_OUTPUT" "$DISCOVERY_OUTPUTS"
        exit 1
      fi
      
      # Parse into array for processing
      IFS=',' read -ra PACKAGE_ARRAY <<< "$PACKAGE_PATHS"
      TOTAL_PACKAGES=${#PACKAGE_ARRAY[@]}
    else
      export GITHUB_OUTPUT="$ORIGINAL_OUTPUT"
      echo "❌ Error: Failed to read discovery results"
      rm -f "$DISCOVERY_OUTPUT" "$DISCOVERY_OUTPUTS"
      exit 1
    fi
    
    rm -f "$DISCOVERY_OUTPUT" "$DISCOVERY_OUTPUTS"
  else
    cat "$DISCOVERY_OUTPUT"
    rm -f "$DISCOVERY_OUTPUT" "$DISCOVERY_OUTPUTS"
    export GITHUB_OUTPUT="$ORIGINAL_OUTPUT"
    echo "❌ Error: Workspace discovery failed"
    exit 1
  fi
  
else
  echo "❌ Error: No packages to process"
  echo ""
  echo "Please either:"
  echo "  1. Provide package-paths input with comma-separated package.json paths"
  echo "  2. Enable workspace-detection (default: true) with workspaces field in root package.json"
  exit 1
fi

# Initialize results array
BUILD_RESULTS="[]"

# Track success/failure
SUCCESSFUL_PACKAGES=0
FAILED_PACKAGES=0

echo "📦 Found $TOTAL_PACKAGES package(s) to process"
echo ""

# Change Detection (only for monorepo with workspace discovery)
# Skip if using explicit package-paths (no directory metadata available)
DISCOVERED_PKG_COUNT=$(echo "$DISCOVERED_PACKAGES" | jq '. | length')
if [ "$CHANGED_ONLY" = "true" ] && [ "$WORKSPACE_DETECTION" = "true" ] && [ "$DISCOVERED_PKG_COUNT" -gt 0 ]; then
  echo "🔍 Running change detection..."
  echo ""
  
  # Run change detection script
  CHANGE_DETECTION_OUTPUT=$(mktemp)
  CHANGE_DETECTION_OUTPUTS=$(mktemp)
  
  # Save current GITHUB_OUTPUT location
  ORIGINAL_OUTPUT="$GITHUB_OUTPUT"
  # Use temporary file for change detection outputs
  export GITHUB_OUTPUT="$CHANGE_DETECTION_OUTPUTS"
  
  # Pass discovered packages to change detection
  export DISCOVERED_PACKAGES_JSON="$DISCOVERED_PACKAGES"
  
  if bash "$ACTION_PATH/scripts/detect-changed-packages.sh" > "$CHANGE_DETECTION_OUTPUT" 2>&1; then
    cat "$CHANGE_DETECTION_OUTPUT"
    
    # Read outputs from temporary file
    if [ -f "$CHANGE_DETECTION_OUTPUTS" ]; then
      CHANGED_PACKAGES_JSON=$(grep "^changed-packages=" "$CHANGE_DETECTION_OUTPUTS" | tail -1 | cut -d= -f2-)
      CHANGED_COUNT=$(grep "^changed-count=" "$CHANGE_DETECTION_OUTPUTS" | tail -1 | cut -d= -f2-)
      ALL_PACKAGES_CHANGED=$(grep "^all-packages-changed=" "$CHANGE_DETECTION_OUTPUTS" | tail -1 | cut -d= -f2-)
      
      # Copy change detection outputs to the original GITHUB_OUTPUT
      export GITHUB_OUTPUT="$ORIGINAL_OUTPUT"
      echo "changed-packages=$CHANGED_PACKAGES_JSON" >> "$GITHUB_OUTPUT"
      echo "changed-count=$CHANGED_COUNT" >> "$GITHUB_OUTPUT"
      
      # Filter packages based on changes
      if [ "$ALL_PACKAGES_CHANGED" = "true" ] || [ "$CHANGED_COUNT" = "-1" ]; then
        echo ""
        echo "📦 Processing all $TOTAL_PACKAGES packages"
        echo ""
      elif [ "$CHANGED_COUNT" = "0" ]; then
        echo ""
        echo "ℹ️  No packages changed - nothing to process"
        echo ""
        # Set empty results and exit successfully
        echo "build-results=[]" >> "$GITHUB_OUTPUT"
        rm -f "$CHANGE_DETECTION_OUTPUT" "$CHANGE_DETECTION_OUTPUTS"
        exit 0
      else
        echo ""
        echo "📦 Processing only $CHANGED_COUNT changed package(s)"
        echo ""
        
        # Validate CHANGED_PACKAGES_JSON is valid JSON
        if ! echo "$CHANGED_PACKAGES_JSON" | jq -e . >/dev/null 2>&1; then
          echo "⚠️  Warning: Invalid JSON in changed packages output"
          echo "    First 100 chars: ${CHANGED_PACKAGES_JSON:0:100}"
          echo "🔄 Falling back to processing all packages"
          echo ""
        else
          # Extract changed package paths into bash array
          mapfile -t CHANGED_PATHS < <(echo "$CHANGED_PACKAGES_JSON" | jq -r '.[].path')
          
          # Build associative array for O(1) membership checks
          declare -A CHANGED_LOOKUP=()
          for changed_path in "${CHANGED_PATHS[@]}"; do
            CHANGED_LOOKUP["$changed_path"]=1
          done
          
          # Filter PACKAGE_ARRAY to only include changed packages
          FILTERED_ARRAY=()
          for pkg_path in "${PACKAGE_ARRAY[@]}"; do
            # Check if this package path is in the changed packages set
            if [ -n "${CHANGED_LOOKUP[$pkg_path]+_}" ]; then
              FILTERED_ARRAY+=("$pkg_path")
            fi
          done
          
          PACKAGE_ARRAY=("${FILTERED_ARRAY[@]}")
          TOTAL_PACKAGES=${#PACKAGE_ARRAY[@]}
          
          if [ "$TOTAL_PACKAGES" -eq 0 ]; then
            echo "ℹ️  No changed packages to process after filtering"
            echo ""
            echo "build-results=[]" >> "$GITHUB_OUTPUT"
            rm -f "$CHANGE_DETECTION_OUTPUT" "$CHANGE_DETECTION_OUTPUTS"
            exit 0
          fi
        fi
      fi
      
      rm -f "$CHANGE_DETECTION_OUTPUT" "$CHANGE_DETECTION_OUTPUTS"
    else
      export GITHUB_OUTPUT="$ORIGINAL_OUTPUT"
      echo "⚠️  Warning: Failed to read change detection results"
      echo "🔄 Falling back to processing all packages"
      echo ""
      echo "changed-packages=[]" >> "$GITHUB_OUTPUT"
      echo "changed-count=-1" >> "$GITHUB_OUTPUT"
      rm -f "$CHANGE_DETECTION_OUTPUT" "$CHANGE_DETECTION_OUTPUTS"
    fi
  else
    cat "$CHANGE_DETECTION_OUTPUT"
    export GITHUB_OUTPUT="$ORIGINAL_OUTPUT"
    echo "⚠️  Warning: Change detection failed"
    echo "🔄 Falling back to processing all packages"
    echo ""
    echo "changed-packages=[]" >> "$GITHUB_OUTPUT"
    echo "changed-count=-1" >> "$GITHUB_OUTPUT"
    rm -f "$CHANGE_DETECTION_OUTPUT" "$CHANGE_DETECTION_OUTPUTS"
  fi
else
  # Change detection disabled or not applicable
  if [ "$CHANGED_ONLY" != "true" ]; then
    echo "ℹ️  Change detection disabled (changed-only: false)"
  elif [ "$WORKSPACE_DETECTION" != "true" ]; then
    echo "ℹ️  Change detection not applicable (workspace-detection: false)"
  fi
  echo "📦 Processing all $TOTAL_PACKAGES packages"
  echo ""
  echo "changed-packages=[]" >> "$GITHUB_OUTPUT"
  echo "changed-count=-1" >> "$GITHUB_OUTPUT"
fi

# Dependency Order Resolution
# Only applicable when workspace-detection is enabled (need package metadata)
if [ "$DEPENDENCY_ORDER" = "true" ] && [ "$WORKSPACE_DETECTION" = "true" ] && [ "$DISCOVERED_PKG_COUNT" -gt 0 ]; then
  echo "🔄 Resolving dependency order..."
  echo ""
  
  # Prepare packages JSON for the Node.js script
  # We need to build a JSON array of packages currently in PACKAGE_ARRAY
  # Match them with the discovered packages metadata
  PACKAGES_FOR_ORDERING="[]"
  
  for pkg_path in "${PACKAGE_ARRAY[@]}"; do
    # Find matching package in DISCOVERED_PACKAGES
    MATCHING_PKG=$(echo "$DISCOVERED_PACKAGES" | jq --arg path "$pkg_path" '.[] | select(.path == $path)')
    
    if [ -n "$MATCHING_PKG" ] && [ "$MATCHING_PKG" != "null" ]; then
      PACKAGES_FOR_ORDERING=$(echo "$PACKAGES_FOR_ORDERING" | jq --argjson pkg "$MATCHING_PKG" '. += [$pkg]')
    fi
  done
  
  # Run dependency order resolution script
  DEP_ORDER_OUTPUT=$(mktemp)
  DEP_ORDER_OUTPUTS=$(mktemp)
  
  # Save current GITHUB_OUTPUT location
  ORIGINAL_OUTPUT="$GITHUB_OUTPUT"
  export GITHUB_OUTPUT="$DEP_ORDER_OUTPUTS"
  
  export PACKAGES_JSON="$PACKAGES_FOR_ORDERING"
  
  if node "$ACTION_PATH/scripts/resolve-dependency-order.js" > "$DEP_ORDER_OUTPUT" 2>&1; then
    cat "$DEP_ORDER_OUTPUT"
    
    # Read ordered packages from output
    if [ -f "$DEP_ORDER_OUTPUTS" ]; then
      ORDERED_PACKAGES_JSON=$(grep "^ordered-packages=" "$DEP_ORDER_OUTPUTS" | tail -1 | cut -d= -f2-)
      
      export GITHUB_OUTPUT="$ORIGINAL_OUTPUT"
      
      if [ -n "$ORDERED_PACKAGES_JSON" ] && [ "$ORDERED_PACKAGES_JSON" != "null" ]; then
        # Update PACKAGE_ARRAY with ordered paths
        IFS=',' read -ra PACKAGE_ARRAY <<< "$(echo "$ORDERED_PACKAGES_JSON" | jq -r '[.[].path] | join(",")')"
        echo "✅ Packages reordered based on dependencies"
      else
        echo "⚠️  Warning: Could not parse ordered packages, using original order"
      fi
    else
      export GITHUB_OUTPUT="$ORIGINAL_OUTPUT"
      echo "⚠️  Warning: Dependency ordering output not found, using original order"
    fi
    
    rm -f "$DEP_ORDER_OUTPUT" "$DEP_ORDER_OUTPUTS"
  else
    cat "$DEP_ORDER_OUTPUT"
    export GITHUB_OUTPUT="$ORIGINAL_OUTPUT"
    echo "❌ Error: Dependency ordering failed"
    rm -f "$DEP_ORDER_OUTPUT" "$DEP_ORDER_OUTPUTS"
    exit 1
  fi
  
  echo ""
elif [ "$DEPENDENCY_ORDER" = "true" ] && [ "$WORKSPACE_DETECTION" != "true" ]; then
  echo "ℹ️  Dependency ordering not applicable (workspace-detection disabled)"
  echo "📦 Using original package order"
  echo ""
elif [ "$DEPENDENCY_ORDER" != "true" ]; then
  echo "ℹ️  Dependency ordering disabled (dependency-order: false)"
  echo "📦 Using discovery order"
  echo ""
fi

# Process each package
for i in "${!PACKAGE_ARRAY[@]}"; do
  PACKAGE_PATH="${PACKAGE_ARRAY[$i]}"
  
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
    RESULT="failed"
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
  
  # Safely parse package name from package.json without aborting the orchestrator on failure
  set +e
  PACKAGE_NAME=$(jq -r '.name' "$PACKAGE_PATH" 2>/dev/null)
  jq_status=$?
  set -e
  
  if [ "$jq_status" -ne 0 ] || [ -z "$PACKAGE_NAME" ] || [ "$PACKAGE_NAME" = "null" ]; then
    echo "❌ Error: Failed to read package name from '$PACKAGE_PATH' (invalid JSON or missing .name)"
    PACKAGE_NAME="unknown"
    PACKAGE_VERSION="unknown"
    RESULT="failed"
    ERROR_MESSAGE="Failed to read package name from package.json (invalid JSON or missing .name)"
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
  
  echo "📋 Package name: $PACKAGE_NAME"
  
  # Set environment for this package
  export PACKAGE_PATH
  
  # Create a temporary output file for this package's steps
  TEMP_OUTPUT=$(mktemp)
  
  # Step 1: Detect flow
  echo "🔍 Detecting build flow..."
  if bash "$ACTION_PATH/scripts/detect-package-flow.sh" > "$TEMP_OUTPUT" 2>&1; then
    cat "$TEMP_OUTPUT"
    
    # Parse outputs from the detect script
    # The script writes to GITHUB_OUTPUT, but we need to capture those values
    # Extract version and tag from the output
    PACKAGE_VERSION=""
    NPM_TAG=""
    
    if [ -f "$GITHUB_OUTPUT" ]; then
      PACKAGE_VERSION=$(grep "^version=" "$GITHUB_OUTPUT" | tail -1 | cut -d= -f2-)
      NPM_TAG=$(grep "^npm-tag=" "$GITHUB_OUTPUT" | tail -1 | cut -d= -f2-)
    fi
    
    # Fallback: parse from temp output if not in GITHUB_OUTPUT
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
    RESULT="failed"
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
  
  # Step 2: Configure registries (always run if tokens are provided, to support private dependencies)
  echo ""
  SKIP_REGISTRY_CONFIG=false
  
  # Skip only if both conditions are met:
  # 1. Publishing is disabled or dry-run mode
  # 2. No tokens are provided (indicating no private registry dependencies)
  if [ "$PUBLISH_ENABLED" != "true" ] || [ "$DRY_RUN" = "true" ]; then
    if [ -z "$NPM_TOKEN" ] && [ -z "$GITHUB_TOKEN" ]; then
      SKIP_REGISTRY_CONFIG=true
      echo "⏭️  Skipping registry configuration (no tokens provided and publish disabled/dry-run)"
    else
      echo "⚙️  Configuring registries (tokens provided for potential private dependencies)..."
    fi
  else
    echo "⚙️  Configuring registries..."
  fi
  
  if [ "$SKIP_REGISTRY_CONFIG" = "false" ]; then
    if bash "$ACTION_PATH/scripts/configure-registries.sh" > "$TEMP_OUTPUT" 2>&1; then
      cat "$TEMP_OUTPUT"
      echo "✅ Registry configuration completed"
    else
      cat "$TEMP_OUTPUT"
      echo "❌ Registry configuration failed"
      RESULT="failed"
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
  fi
  
  # Step 3: Build and publish
  echo ""
  echo "🏗️  Building and publishing..."
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
    echo "🔒 Running security audit..."
    if node "$ACTION_PATH/scripts/audit-package.js" > "$TEMP_OUTPUT" 2>&1; then
      cat "$TEMP_OUTPUT"
      echo "✅ Security audit completed"
    else
      cat "$TEMP_OUTPUT"
      if [ "$FAIL_ON_AUDIT" = "true" ]; then
        echo "❌ Security audit failed and fail-on-audit is enabled; marking package as failed"
        # Only adjust counts if this package was previously considered successful
        if [ "$RESULT" = "success" ]; then
          RESULT="failed"
          ERROR_MESSAGE="Security audit failed"
          SUCCESSFUL_PACKAGES=$((SUCCESSFUL_PACKAGES - 1))
          FAILED_PACKAGES=$((FAILED_PACKAGES + 1))
        fi
      else
        echo "⚠️  Security audit failed (but continuing)"
        # Don't mark as failed if only audit fails and fail-on-audit is disabled
      fi
    fi
  else
    echo "⏭️  Security audit disabled"
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
echo "build-results=$(echo "$BUILD_RESULTS" | jq -c '.')" >> "$GITHUB_OUTPUT"

# Exit with error if any package failed
if [ "$FAILED_PACKAGES" -gt 0 ]; then
  echo "❌ Monorepo build completed with $FAILED_PACKAGES failure(s)"
  exit 1
else
  echo "✅ All packages processed successfully"
  exit 0
fi
