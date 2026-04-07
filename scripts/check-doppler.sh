#!/usr/bin/env bash
set -euo pipefail

# Default warning message
DEFAULT_MESSAGE="Doppler not detected in this repository.

This repository does not appear to be using Doppler for secrets management. If your team uses Doppler, please follow the setup guide: https://docs.doppler.com/docs/getting-started"

MESSAGE="${INPUT_CUSTOM_MESSAGE:-$DEFAULT_MESSAGE}"

# --- Check 1: Config file ---
if [ -f "$GITHUB_WORKSPACE/doppler.yaml" ] || [ -f "$GITHUB_WORKSPACE/doppler.yml" ]; then
  echo "Doppler config file found"
  echo "doppler-detected=true" >> "${GITHUB_OUTPUT:-/dev/null}"
  exit 0
fi

# --- Check 2: Workflow references ---
WORKFLOW_DIR="$GITHUB_WORKSPACE/.github/workflows"
if [ -d "$WORKFLOW_DIR" ]; then
  if grep -rE --include='*.yml' --include='*.yaml' 'dopplerhq/|doppler run' "$WORKFLOW_DIR" 2>/dev/null | grep -vq 'dopplerhq/doppler-usage-check'; then
    echo "Doppler reference found in workflow files"
    echo "doppler-detected=true" >> "${GITHUB_OUTPUT:-/dev/null}"
    exit 0
  fi
fi

# --- Check 3: Secrets and variables API ---
# Check variables
VARIABLES_RESPONSE=$(gh api --paginate "repos/${GITHUB_REPOSITORY}/actions/variables" 2>/dev/null) && {
  if echo "$VARIABLES_RESPONSE" | grep -q '"name":"DOPPLER_'; then
    echo "DOPPLER_ variable found via API"
    echo "doppler-detected=true" >> "${GITHUB_OUTPUT:-/dev/null}"
    exit 0
  fi
} || {
  echo "Unable to list repository variables — token may lack sufficient permissions."
}

# Check secrets
SECRETS_RESPONSE=$(gh api --paginate "repos/${GITHUB_REPOSITORY}/actions/secrets" 2>/dev/null) && {
  if echo "$SECRETS_RESPONSE" | grep -q '"name":"DOPPLER_'; then
    echo "DOPPLER_ secret found via API"
    echo "doppler-detected=true" >> "${GITHUB_OUTPUT:-/dev/null}"
    exit 0
  fi
} || {
  echo "Unable to list repository secrets — token may lack sufficient permissions."
}

# --- No signals found ---
echo "::warning::${MESSAGE}"
echo "doppler-detected=false" >> "${GITHUB_OUTPUT:-/dev/null}"

# Create a neutral check run for visibility on the PR
gh api "repos/${GITHUB_REPOSITORY}/check-runs" \
  --method POST \
  --field name="Doppler Usage Check" \
  --field head_sha="${HEAD_SHA}" \
  --field conclusion="neutral" \
  --field "output[title]=Doppler not detected" \
  --field "output[summary]=${MESSAGE}" 2>/dev/null || {
  echo "Unable to create check run — token may lack checks:write permission or this may be a fork PR."
}

exit 0
