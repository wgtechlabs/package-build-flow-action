#!/bin/bash
set -e

# Workspace Discovery Script
# Reads workspaces field from root package.json and discovers all publishable packages

echo "🔍 Discovering workspace packages..."
echo ""

# Validate root package.json path
ROOT_PACKAGE_PATH="${PACKAGE_PATH:-./package.json}"

if [ ! -f "$ROOT_PACKAGE_PATH" ]; then
  echo "❌ Error: Root package.json not found at '$ROOT_PACKAGE_PATH'"
  exit 1
fi

echo "📄 Reading workspace patterns from: $ROOT_PACKAGE_PATH"

# Extract workspaces field from package.json
# Handle both array format and object format (with "packages" key)
set +e
WORKSPACES_RAW=$(jq -r '.workspaces' "$ROOT_PACKAGE_PATH" 2>/dev/null)
jq_status=$?
set -e

if [ "$jq_status" -ne 0 ]; then
  echo "❌ Error: Failed to parse package.json (invalid JSON)"
  exit 1
fi

if [ "$WORKSPACES_RAW" = "null" ] || [ -z "$WORKSPACES_RAW" ]; then
  echo "❌ Error: No 'workspaces' field found in root package.json"
  echo "Expected format:"
  echo '  "workspaces": ["core", "apps/*", "plugins/*"]'
  echo "or:"
  echo '  "workspaces": {"packages": ["core", "apps/*"]}'
  exit 1
fi

# Handle object format (Yarn berry/npm v7+)
WORKSPACES_TYPE=$(echo "$WORKSPACES_RAW" | jq -r 'type')
if [ "$WORKSPACES_TYPE" = "object" ]; then
  # Extract packages array from object
  WORKSPACES=$(echo "$WORKSPACES_RAW" | jq -r '.packages // empty | .[]' 2>/dev/null)
  if [ -z "$WORKSPACES" ]; then
    echo "❌ Error: workspaces is an object but has no 'packages' array"
    exit 1
  fi
elif [ "$WORKSPACES_TYPE" = "array" ]; then
  # Direct array format
  WORKSPACES=$(echo "$WORKSPACES_RAW" | jq -r '.[]' 2>/dev/null)
else
  echo "❌ Error: workspaces field must be an array or object with packages array"
  exit 1
fi

if [ -z "$WORKSPACES" ]; then
  echo "❌ Error: No workspace patterns found"
  exit 1
fi

echo "📋 Workspace patterns:"
echo "$WORKSPACES" | sed 's/^/  - /'
echo ""

# Get the directory containing the root package.json
ROOT_DIR=$(dirname "$ROOT_PACKAGE_PATH")
cd "$ROOT_DIR"

# Discover packages
DISCOVERED_PACKAGES="[]"
TOTAL_FOUND=0
SKIPPED_PRIVATE=0

echo "🔎 Resolving workspace patterns..."
echo ""

# Process each workspace pattern
while IFS= read -r pattern; do
  pattern=$(echo "$pattern" | xargs) # Trim whitespace
  
  if [ -z "$pattern" ]; then
    continue
  fi
  
  echo "  Pattern: $pattern"
  
  # Check if pattern contains glob characters
  if [[ "$pattern" == *"*"* ]] || [[ "$pattern" == *"?"* ]]; then
    # Glob pattern - find all matching directories
    # Use find with pattern matching
    # Convert glob pattern to find-compatible pattern
    # e.g., "apps/*" becomes finding all dirs in apps/
    
    # Extract base directory and glob part
    if [[ "$pattern" == */* ]]; then
      BASE_DIR="${pattern%/*}"
      GLOB_PART="${pattern##*/}"
    else
      BASE_DIR="."
      GLOB_PART="$pattern"
    fi
    
    # Find directories matching the pattern
    if [ -d "$BASE_DIR" ]; then
      # Use shell globbing by temporarily disabling nomatch error
      shopt -s nullglob 2>/dev/null || true
      
      for dir in $pattern; do
        if [ -d "$dir" ]; then
          PKG_PATH="$dir/package.json"
          if [ -f "$PKG_PATH" ]; then
            # Check if package is private
            IS_PRIVATE=$(jq -r '.private // false' "$PKG_PATH" 2>/dev/null)
            
            if [ "$IS_PRIVATE" = "true" ]; then
              echo "    ⏭️  Skipping $PKG_PATH (private: true)"
              SKIPPED_PRIVATE=$((SKIPPED_PRIVATE + 1))
              continue
            fi
            
            # Extract package metadata
            PKG_NAME=$(jq -r '.name // "unknown"' "$PKG_PATH" 2>/dev/null)
            PKG_VERSION=$(jq -r '.version // "0.0.0"' "$PKG_PATH" 2>/dev/null)
            
            # Normalize path (remove leading ./)
            PKG_PATH_NORMALIZED="${PKG_PATH#./}"
            PKG_DIR="${dir#./}"
            
            echo "    ✅ Found: $PKG_NAME ($PKG_PATH_NORMALIZED)"
            
            # Add to discovered packages
            DISCOVERED_PACKAGES=$(echo "$DISCOVERED_PACKAGES" | jq \
              --arg name "$PKG_NAME" \
              --arg version "$PKG_VERSION" \
              --arg path "$PKG_PATH_NORMALIZED" \
              --arg dir "$PKG_DIR" \
              '. += [{"name": $name, "version": $version, "path": $path, "dir": $dir}]')
            
            TOTAL_FOUND=$((TOTAL_FOUND + 1))
          fi
        fi
      done
      
      shopt -u nullglob 2>/dev/null || true
    fi
  else
    # Direct path - check if it's a directory
    if [ -d "$pattern" ]; then
      PKG_PATH="$pattern/package.json"
      
      if [ -f "$PKG_PATH" ]; then
        # Check if package is private
        IS_PRIVATE=$(jq -r '.private // false' "$PKG_PATH" 2>/dev/null)
        
        if [ "$IS_PRIVATE" = "true" ]; then
          echo "    ⏭️  Skipping $PKG_PATH (private: true)"
          SKIPPED_PRIVATE=$((SKIPPED_PRIVATE + 1))
          continue
        fi
        
        # Extract package metadata
        PKG_NAME=$(jq -r '.name // "unknown"' "$PKG_PATH" 2>/dev/null)
        PKG_VERSION=$(jq -r '.version // "0.0.0"' "$PKG_PATH" 2>/dev/null)
        
        # Normalize path (remove leading ./)
        PKG_PATH_NORMALIZED="${PKG_PATH#./}"
        PKG_DIR="${pattern#./}"
        
        echo "    ✅ Found: $PKG_NAME ($PKG_PATH_NORMALIZED)"
        
        # Add to discovered packages
        DISCOVERED_PACKAGES=$(echo "$DISCOVERED_PACKAGES" | jq \
          --arg name "$PKG_NAME" \
          --arg version "$PKG_VERSION" \
          --arg path "$PKG_PATH_NORMALIZED" \
          --arg dir "$PKG_DIR" \
          '. += [{"name": $name, "version": $version, "path": $path, "dir": $dir}]')
        
        TOTAL_FOUND=$((TOTAL_FOUND + 1))
      else
        echo "    ⚠️  Warning: No package.json found in $pattern"
      fi
    else
      echo "    ⚠️  Warning: Directory not found: $pattern"
    fi
  fi
done <<< "$WORKSPACES"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 Discovery Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Total packages found: $TOTAL_FOUND"
echo "Private packages skipped: $SKIPPED_PRIVATE"
echo ""

if [ "$TOTAL_FOUND" -eq 0 ]; then
  echo "❌ Error: No publishable packages discovered"
  echo "All packages may have 'private: true' or no packages found in workspace patterns"
  exit 1
fi

echo "Discovered packages:"
echo "$DISCOVERED_PACKAGES" | jq '.'
echo ""

# Set outputs
echo "discovered-packages=$(echo "$DISCOVERED_PACKAGES" | jq -c '.')" >> "$GITHUB_OUTPUT"
echo "package-count=$TOTAL_FOUND" >> "$GITHUB_OUTPUT"

# Export for use in monorepo orchestrator
# Convert to comma-separated package paths
PACKAGE_PATHS=$(echo "$DISCOVERED_PACKAGES" | jq -r '.[].path' | tr '\n' ',' | sed 's/,$//')
echo "DISCOVERED_PACKAGE_PATHS=$PACKAGE_PATHS"

echo "✅ Workspace discovery completed"
