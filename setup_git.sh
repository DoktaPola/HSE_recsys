#!/usr/bin/env bash
# One-shot setup: init git, commit everything, link to GitHub, push branch tmp.
# Usage: bash setup_git.sh [REPO_URL]
#   REPO_URL defaults to https://github.com/DoktaPola/HSE_recsys.git
set -euo pipefail

REPO_URL="${1:-https://github.com/DoktaPola/HSE_recsys.git}"
BRANCH="tmp"

cd "$(dirname "$0")"

# 1. Create the repo on GitHub if gh is installed/authed and it doesn't exist yet
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  SLUG="${REPO_URL#https://github.com/}"; SLUG="${SLUG%.git}"
  if ! gh repo view "$SLUG" >/dev/null 2>&1; then
    echo "Creating GitHub repo $SLUG (private)..."
    gh repo create "$SLUG" --private
  fi
fi

# 2. Init repo with 'tmp' as the initial branch
if [ -d .git ]; then
  echo "Git repo already initialized."
else
  git init -b "$BRANCH" 2>/dev/null || { git init && git symbolic-ref HEAD "refs/heads/$BRANCH"; }
fi

# 3. Commit everything
git add .
git commit -m "Initial commit

Co-Authored-By: Claude Code <noreply@anthropic.com>" || echo "Nothing to commit"

# 4. Link the remote
if git remote | grep -qx origin; then
  git remote set-url origin "$REPO_URL"
else
  git remote add origin "$REPO_URL"
fi

# 5. Push tmp and set upstream (this is what links the branch to the remote)
echo "Pushing $BRANCH to $REPO_URL ..."
if GIT_TERMINAL_PROMPT=0 git push -u origin "$BRANCH"; then
  echo ""
  echo "Done. Branch '$BRANCH' is linked to origin/$BRANCH — git pull/push work without args now."
else
  echo ""
  echo "Push failed. Most likely reasons:"
  echo "  1) The repo $REPO_URL doesn't exist — create it empty on github.com (without README), then run:"
  echo "       git push -u origin $BRANCH"
  echo "  2) Not authenticated — run 'gh auth login', or add a PAT / SSH key."
  exit 1
fi
