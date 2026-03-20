#!/bin/bash
set -euo pipefail

ACTOR="${ACTOR:-}"
BOT_DETECTION="${BOT_DETECTION:-true}"

if [ -z "${GITHUB_OUTPUT:-}" ]; then
  echo "❌ GITHUB_OUTPUT is required" >&2
  exit 1
fi

if [ "$BOT_DETECTION" != "true" ]; then
  echo "is-bot=false" >> "$GITHUB_OUTPUT"
  echo "ℹ️  Bot detection is disabled"
  exit 0
fi

if [[ "$ACTOR" == *"[bot]"* ]]; then
  echo "is-bot=true" >> "$GITHUB_OUTPUT"
  echo "build-skip-reason=Bot actor: ${ACTOR}" >> "$GITHUB_OUTPUT"
  echo "⚠️  Bot actor detected (${ACTOR}) — running in validation-only mode (no publish)"
else
  echo "is-bot=false" >> "$GITHUB_OUTPUT"
  echo "ℹ️  Actor '${ACTOR}' is not a bot"
fi