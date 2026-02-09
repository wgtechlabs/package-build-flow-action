#!/bin/bash
set -e

# Detect NPM Package Build Flow
# Implements intelligent flow detection based on GitHub context

echo "🔍 Detecting build flow..."

# Parse GitHub context
EVENT_NAME=$(echo "$GITHUB_CONTEXT" | jq -r '.event_name')
REF_NAME=$(echo "$GITHUB_CONTEXT" | jq -r '.ref_name // .ref // ""' | sed 's|refs/heads/||')
BASE_REF=$(echo "$GITHUB_CONTEXT" | jq -r '.base_ref // ""' | sed 's|refs/heads/||')
HEAD_REF=$(echo "$GITHUB_CONTEXT" | jq -r '.head_ref // ""')
SHA=$(echo "$GITHUB_CONTEXT" | jq -r '.sha')
SHORT_SHA="${SHA:0:7}"

# Get PR details if applicable
if [ "$EVENT_NAME" = "pull_request" ]; then
  PR_BASE=$(echo "$GITHUB_CONTEXT" | jq -r '.event.pull_request.base.ref')
  PR_HEAD=$(echo "$GITHUB_CONTEXT" | jq -r '.event.pull_request.head.ref')
  echo "📋 PR detected: $PR_HEAD -> $PR_BASE"
elif [ "$EVENT_NAME" = "release" ]; then
  RELEASE_TAG=$(echo "$GITHUB_CONTEXT" | jq -r '.event.release.tag_name')
  RELEASE_PRERELEASE=$(echo "$GITHUB_CONTEXT" | jq -r '.event.release.prerelease')
  echo "🚀 Release detected: tag=$RELEASE_TAG prerelease=$RELEASE_PRERELEASE"
  PR_BASE=""
  PR_HEAD=""
else
  PR_BASE=""
  PR_HEAD=""
  echo "📌 Push detected: branch=$REF_NAME"
fi

# Read current version from package.json
if [ ! -f "$PACKAGE_PATH" ]; then
  echo "❌ Error: package.json not found at $PACKAGE_PATH"
  exit 1
fi

BASE_VERSION=$(jq -r '.version' "$PACKAGE_PATH")
echo "📦 Current package version: $BASE_VERSION"

# Extract version components
MAJOR=$(echo "$BASE_VERSION" | cut -d. -f1)
MINOR=$(echo "$BASE_VERSION" | cut -d. -f2)
PATCH=$(echo "$BASE_VERSION" | cut -d. -f3 | cut -d- -f1)

# Function to increment patch version
increment_patch() {
  echo "$MAJOR.$MINOR.$((PATCH + 1))"
}

# Function to extract prerelease tag from version (e.g., "beta" from "1.0.0-beta.1")
extract_prerelease_tag() {
  local version=$1
  # Match semver format with prerelease identifier: x.y.z<identifier>[.<identifier>][+build]
  # Capture only the first prerelease identifier segment (alphanumerics and hyphens)
  if [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+-([0-9A-Za-z-]+) ]]; then
    echo "${BASH_REMATCH[1]}"
  else
    echo ""
  fi
}

# Detect build flow type
BUILD_FLOW_TYPE=""
PACKAGE_VERSION=""
NPM_TAG=""

if [ "$EVENT_NAME" = "release" ]; then
  # GitHub Release event
  BUILD_FLOW_TYPE="release"
  
  # Extract version from tag
  # Remove leading 'v' only for semver-style tags like v1.2.3; otherwise keep tag as-is
  if [[ "$RELEASE_TAG" =~ ^v[0-9] ]]; then
    RELEASE_VERSION="${RELEASE_TAG#v}"
  else
    RELEASE_VERSION="$RELEASE_TAG"
  fi
  PACKAGE_VERSION="$RELEASE_VERSION"
  
  # Determine npm tag based on version and prerelease status
  if [ "$RELEASE_PRERELEASE" = "true" ]; then
    # For pre-releases, extract the prerelease identifier (e.g., "beta" from "1.0.0-beta.1")
    PRERELEASE_TAG=$(extract_prerelease_tag "$RELEASE_VERSION")
    if [ -n "$PRERELEASE_TAG" ]; then
      NPM_TAG="$PRERELEASE_TAG"
      echo "🎭 Flow: Pre-release with tag '$PRERELEASE_TAG'"
    else
      # No prerelease identifier found, use 'prerelease' as fallback
      NPM_TAG="prerelease"
      echo "🎭 Flow: Pre-release (generic)"
    fi
  else
    # Standard release uses 'latest' tag
    NPM_TAG="latest"
    echo "🎉 Flow: Production release"
  fi
  
  echo "📦 Release Version: $PACKAGE_VERSION"
  echo "🏷️  NPM Tag: $NPM_TAG"
elif [ "$EVENT_NAME" = "pull_request" ]; then
  if [ "$PR_BASE" = "$DEV_BRANCH" ]; then
    # PR targeting dev branch
    BUILD_FLOW_TYPE="pr"
    PACKAGE_VERSION="${BASE_VERSION}-pr.${SHORT_SHA}"
    NPM_TAG="pr"
    echo "🔀 Flow: PR to dev branch"
  elif [ "$PR_BASE" = "$MAIN_BRANCH" ]; then
    if [ "$PR_HEAD" = "$DEV_BRANCH" ]; then
      # PR from dev to main
      BUILD_FLOW_TYPE="dev"
      PACKAGE_VERSION="${BASE_VERSION}-dev.${SHORT_SHA}"
      NPM_TAG="dev"
      echo "🚀 Flow: Dev to main PR"
    else
      # PR to main (not from dev)
      BUILD_FLOW_TYPE="patch"
      NEXT_VERSION=$(increment_patch)
      PACKAGE_VERSION="${NEXT_VERSION}-patch.${SHORT_SHA}"
      NPM_TAG="patch"
      echo "🔧 Flow: Patch PR to main"
    fi
  else
    # PR to other branch
    BUILD_FLOW_TYPE="wip"
    PACKAGE_VERSION="${BASE_VERSION}-wip.${SHORT_SHA}"
    NPM_TAG="wip"
    echo "🚧 Flow: WIP PR"
  fi
elif [ "$EVENT_NAME" = "push" ]; then
  if [ "$REF_NAME" = "$MAIN_BRANCH" ]; then
    # Push to main branch - staging
    BUILD_FLOW_TYPE="staging"
    # Get staging number (use last 6 digits of timestamp)
    STAGING_NUMBER=$(date +%s)
    STAGING_NUMBER=${STAGING_NUMBER: -6}
    PACKAGE_VERSION="${BASE_VERSION}-staging.${STAGING_NUMBER}"
    NPM_TAG="staging"
    echo "🎯 Flow: Staging release (push to main)"
  elif [ "$REF_NAME" = "$DEV_BRANCH" ]; then
    # Push to dev branch
    BUILD_FLOW_TYPE="dev"
    PACKAGE_VERSION="${BASE_VERSION}-dev.${SHORT_SHA}"
    NPM_TAG="dev"
    echo "🔨 Flow: Dev branch push"
  else
    # Push to other branch
    BUILD_FLOW_TYPE="wip"
    PACKAGE_VERSION="${BASE_VERSION}-wip.${SHORT_SHA}"
    NPM_TAG="wip"
    echo "🚧 Flow: WIP branch push"
  fi
else
  # Other events
  BUILD_FLOW_TYPE="wip"
  PACKAGE_VERSION="${BASE_VERSION}-wip.${SHORT_SHA}"
  NPM_TAG="wip"
  echo "❓ Flow: Unknown event type"
fi

# Version prefix is not applied to the package version because it
# produces invalid semver (e.g., v1.0.0) that npm rejects.
if [ -n "$VERSION_PREFIX" ]; then
  echo "⚠️  version-prefix ('$VERSION_PREFIX') is ignored — npm requires valid semver versions"
fi

echo ""
echo "✅ Flow Detection Complete:"
echo "  Build Flow Type: $BUILD_FLOW_TYPE"
echo "  Package Version: $PACKAGE_VERSION"
echo "  NPM Tag: $NPM_TAG"
echo "  Short SHA: $SHORT_SHA"
echo ""

# Set GitHub Actions outputs
echo "version=$PACKAGE_VERSION" >> "$GITHUB_OUTPUT"
echo "npm-tag=$NPM_TAG" >> "$GITHUB_OUTPUT"
echo "build-flow-type=$BUILD_FLOW_TYPE" >> "$GITHUB_OUTPUT"
echo "short-sha=$SHORT_SHA" >> "$GITHUB_OUTPUT"
