#!/usr/bin/env bash
set -euo pipefail

: "${GH_TOKEN:?GH_TOKEN is required}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"

# Get latest draft release body from current repo
DRAFT_RELEASE=$(gh api \
  -H "Accept: application/vnd.github+json" \
  "/repos/${GITHUB_REPOSITORY}/releases" \
  --jq 'map(select(.draft == true))[0].body' \
)

if [ -z "${DRAFT_RELEASE}" ]; then
  CHANGELOG="## What's Changed\n\n- New release of Osaurus v${VERSION}"
else
  CHANGELOG="${DRAFT_RELEASE}"
fi

{
  echo "changelog<<EOF"
  printf '%s\n' "$CHANGELOG"
  echo "EOF"
} >> "$GITHUB_OUTPUT"

# Delete all draft releases
echo "Cleaning up all draft releases..."
gh api \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "/repos/${GITHUB_REPOSITORY}/releases" \
  --jq '.[] | select(.draft == true) | .id' | \
while read -r DRAFT_ID; do
  if [ -n "$DRAFT_ID" ]; then
    gh api \
      --method DELETE \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "/repos/${GITHUB_REPOSITORY}/releases/$DRAFT_ID" \
      2>/dev/null || true
  fi
done


