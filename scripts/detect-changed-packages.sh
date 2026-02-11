#!/bin/bash
set -e

# Detect Changed Packages Script
# Determines which packages have changed based on git diff

echo "🔍 Detecting changed packages..."
echo ""

# Parse GitHub context
EVENT_NAME=$(echo "$GITHUB_CONTEXT" | jq -r '.event_name')
REF_NAME=$(echo "$GITHUB_CONTEXT" | jq -r '.ref_name // .ref // ""' | sed 's|refs/heads/||')
SHA=$(echo "$GITHUB_CONTEXT" | jq -r '.sha')

echo "📋 Event: $EVENT_NAME"
echo "📋 Ref: $REF_NAME"
echo "📋 SHA: $SHA"
echo ""

# Root config files that should mark ALL packages as changed
ROOT_CONFIG_FILES=(
  "package.json"
  "tsconfig.json"
  "tsconfig.base.json"
  ".npmrc"
  "yarn.lock"
  "package-lock.json"
  "pnpm-lock.yaml"
  "bun.lockb"
)

# Determine comparison base depending on the GitHub event
COMPARE_BASE=""
SHALLOW_CLONE=false

case "$EVENT_NAME" in
  pull_request)
    # Compare against the PR base branch
    PR_BASE=$(echo "$GITHUB_CONTEXT" | jq -r '.event.pull_request.base.sha')
    COMPARE_BASE="$PR_BASE"
    echo "🔀 Pull request detected - comparing against base: $COMPARE_BASE"
    ;;
  
  push)
    # Compare against the previous commit (HEAD~1)
    # But first check if we have history
    if git rev-parse --verify HEAD~1 >/dev/null 2>&1; then
      COMPARE_BASE="HEAD~1"
      echo "📤 Push detected - comparing against previous commit: $COMPARE_BASE"
    else
      echo "⚠️  First commit detected (no HEAD~1)"
      SHALLOW_CLONE=true
    fi
    ;;
  
  release)
    # Compare against the previous git tag
    # Find the most recent tag before the current one
    CURRENT_TAG=$(echo "$GITHUB_CONTEXT" | jq -r '.event.release.tag_name // ""')
    
    if [ -z "$CURRENT_TAG" ]; then
      echo "⚠️  No release tag found in event context"
      SHALLOW_CLONE=true
    else
      echo "🚀 Release detected: $CURRENT_TAG"
      
      # Get all tags sorted by version
      set +e
      PREVIOUS_TAG=$(git tag --sort=-version:refname | grep -Fxv "${CURRENT_TAG}" | head -n 1)
      set -e
      
      if [ -n "$PREVIOUS_TAG" ]; then
        COMPARE_BASE="$PREVIOUS_TAG"
        echo "📊 Comparing against previous tag: $COMPARE_BASE"
      else
        echo "⚠️  No previous tag found"
        SHALLOW_CLONE=true
      fi
    fi
    ;;
  
  *)
    echo "⚠️  Unsupported event type: $EVENT_NAME"
    SHALLOW_CLONE=true
    ;;
esac

# Handle shallow clones - fetch enough history for comparison
if [ -z "$COMPARE_BASE" ] || [ "$SHALLOW_CLONE" = true ]; then
  echo ""
  echo "⚠️  No comparison base available or shallow clone detected"
  
  # Try to fetch history if we're in a shallow clone
  if [ -d ".git" ] && git rev-parse --is-shallow-repository 2>/dev/null | grep -q true; then
    echo "🔄 Attempting to fetch history..."
    
    set +e
    case "$EVENT_NAME" in
      pull_request)
        # Prefer fetching the specific PR base commit SHA for deterministic diffs
        PR_BASE_SHA=$(echo "$GITHUB_CONTEXT" | jq -r '.event.pull_request.base.sha // empty')
        fetch_status=1
        if [ -n "$PR_BASE_SHA" ]; then
          git fetch --depth=100 origin "$PR_BASE_SHA" 2>/dev/null
          fetch_status=$?
          if [ "$fetch_status" -eq 0 ]; then
            COMPARE_BASE="$PR_BASE_SHA"
            echo "✅ Successfully fetched base commit: $COMPARE_BASE"
          fi
        fi

        # Fallback: fetch PR base branch ref if fetching by SHA failed
        if [ -z "$COMPARE_BASE" ]; then
          PR_BASE_REF=$(echo "$GITHUB_CONTEXT" | jq -r '.event.pull_request.base.ref')
          git fetch --depth=100 origin "$PR_BASE_REF" 2>/dev/null
          fetch_status=$?
          if [ "$fetch_status" -eq 0 ]; then
            COMPARE_BASE="origin/$PR_BASE_REF"
            echo "✅ Successfully fetched base branch: $COMPARE_BASE"
          fi
        fi
        ;;
      
      push)
        # Try to unshallow
        git fetch --unshallow 2>/dev/null || git fetch --depth=100 2>/dev/null
        fetch_status=$?
        if [ "$fetch_status" -eq 0 ] && git rev-parse --verify HEAD~1 >/dev/null 2>&1; then
          COMPARE_BASE="HEAD~1"
          echo "✅ Successfully fetched history, using: $COMPARE_BASE"
        fi
        ;;
      
      release)
        # Fetch tags
        git fetch --tags --depth=100 2>/dev/null
        fetch_status=$?
        if [ "$fetch_status" -eq 0 ] && [ -n "$CURRENT_TAG" ]; then
          PREVIOUS_TAG=$(git tag --sort=-version:refname | grep -Fxv "${CURRENT_TAG}" | head -n 1)
          if [ -n "$PREVIOUS_TAG" ]; then
            COMPARE_BASE="$PREVIOUS_TAG"
            echo "✅ Successfully fetched tags, using: $COMPARE_BASE"
          fi
        fi
        ;;
    esac
    set -e
  fi
  
  # If still no comparison base, fall back to all packages
  if [ -z "$COMPARE_BASE" ]; then
    echo "⚠️  Could not establish comparison base"
    echo "🔄 Falling back to processing ALL packages"
    echo ""
    echo "changed-packages=[]" >> "$GITHUB_OUTPUT"
    echo "changed-count=-1" >> "$GITHUB_OUTPUT"
    echo "all-packages-changed=true" >> "$GITHUB_OUTPUT"
    exit 0
  fi
fi

echo ""
echo "📊 Running git diff: $COMPARE_BASE..HEAD"
echo ""

# Run git diff to get changed files
set +e
CHANGED_FILES=$(git diff --name-only "$COMPARE_BASE"..HEAD 2>&1)
diff_status=$?
set -e

if [ "$diff_status" -ne 0 ]; then
  echo "❌ Error: git diff failed"
  echo "$CHANGED_FILES"
  echo ""
  echo "🔄 Falling back to processing ALL packages"
  echo "changed-packages=[]" >> "$GITHUB_OUTPUT"
  echo "changed-count=-1" >> "$GITHUB_OUTPUT"
  echo "all-packages-changed=true" >> "$GITHUB_OUTPUT"
  exit 0
fi

if [ -z "$CHANGED_FILES" ]; then
  echo "ℹ️  No changed files detected"
  echo ""
  echo "changed-packages=[]" >> "$GITHUB_OUTPUT"
  echo "changed-count=0" >> "$GITHUB_OUTPUT"
  echo "all-packages-changed=false" >> "$GITHUB_OUTPUT"
  exit 0
fi

echo "📝 Changed files:"
echo "$CHANGED_FILES" | sed 's/^/  /'
echo ""

# Check if any root config files changed
ALL_PACKAGES_CHANGED=false
for config_file in "${ROOT_CONFIG_FILES[@]}"; do
  if echo "$CHANGED_FILES" | grep -Fxq "$config_file"; then
    echo "⚠️  Root config file changed: $config_file"
    ALL_PACKAGES_CHANGED=true
  fi
done

if [ "$ALL_PACKAGES_CHANGED" = true ]; then
  echo ""
  echo "🔄 Root configuration changed - marking ALL packages as changed"
  echo "changed-packages=[]" >> "$GITHUB_OUTPUT"
  echo "changed-count=-1" >> "$GITHUB_OUTPUT"
  echo "all-packages-changed=true" >> "$GITHUB_OUTPUT"
  exit 0
fi

# Now we need the list of discovered packages to map files to packages
# This should be passed as an environment variable DISCOVERED_PACKAGES_JSON
if [ -z "$DISCOVERED_PACKAGES_JSON" ] || [ "$DISCOVERED_PACKAGES_JSON" = "null" ] || [ "$DISCOVERED_PACKAGES_JSON" = "[]" ]; then
  echo "⚠️  No discovered packages available for filtering"
  echo "🔄 Falling back to processing ALL packages"
  echo ""
  echo "changed-packages=[]" >> "$GITHUB_OUTPUT"
  echo "changed-count=-1" >> "$GITHUB_OUTPUT"
  echo "all-packages-changed=true" >> "$GITHUB_OUTPUT"
  exit 0
fi

echo "📦 Mapping changed files to packages..."
echo ""

# Parse discovered packages and check which ones have changes
CHANGED_PACKAGES="[]"
CHANGED_COUNT=0

# Use jq to iterate through packages
PACKAGE_COUNT=$(echo "$DISCOVERED_PACKAGES_JSON" | jq 'length')

for ((i=0; i<PACKAGE_COUNT; i++)); do
  PKG_NAME=$(echo "$DISCOVERED_PACKAGES_JSON" | jq -r ".[$i].name")
  PKG_DIR=$(echo "$DISCOVERED_PACKAGES_JSON" | jq -r ".[$i].dir")
  PKG_PATH=$(echo "$DISCOVERED_PACKAGES_JSON" | jq -r ".[$i].path")
  
  # Normalize directory path (remove trailing slash)
  PKG_DIR="${PKG_DIR%/}"
  
  # Check if any changed file is under this package directory
  PACKAGE_CHANGED=false
  
  while IFS= read -r changed_file; do
    # Check if the changed file path starts with the package directory OR
    # if the changed file is the package.json itself
    # PKG_DIR is like "packages/pkg1" and PKG_PATH is like "packages/pkg1/package.json"
    if [[ "$changed_file" == "$PKG_DIR/"* ]] || [[ "$changed_file" == "$PKG_PATH" ]]; then
      PACKAGE_CHANGED=true
      break
    fi
  done <<< "$CHANGED_FILES"
  
  if [ "$PACKAGE_CHANGED" = true ]; then
    echo "  ✅ $PKG_NAME (changes detected in $PKG_DIR)"
    CHANGED_PACKAGES=$(echo "$CHANGED_PACKAGES" | jq --arg name "$PKG_NAME" --arg path "$PKG_PATH" '. += [{"name": $name, "path": $path}]')
    CHANGED_COUNT=$((CHANGED_COUNT + 1))
  else
    echo "  ⏭️  $PKG_NAME (no changes)"
  fi
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 Change Detection Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Changed packages: $CHANGED_COUNT"
echo ""

if [ "$CHANGED_COUNT" -eq 0 ]; then
  echo "ℹ️  No packages changed - changes may be outside package directories"
fi

# Set outputs
echo "changed-packages=$(echo "$CHANGED_PACKAGES" | jq -c '.')" >> "$GITHUB_OUTPUT"
echo "changed-count=$CHANGED_COUNT" >> "$GITHUB_OUTPUT"
echo "all-packages-changed=false" >> "$GITHUB_OUTPUT"

echo "✅ Change detection completed"
