#!/bin/bash
#
# deploy-web.sh — push web/public/ to Vercel (production).
#
# Prereqs:
#   - vercel CLI installed (`npm i -g vercel` or via Homebrew)
#   - `vercel login` once, then `vercel link` from this directory
#
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
WEB_DIR="$HERE/../web/public"

cd "$HERE/.."
if ! command -v vercel >/dev/null 2>&1; then
  echo "vercel CLI not found. Install with: npm i -g vercel" >&2
  exit 1
fi

echo "==> vercel --prod (deploying $WEB_DIR)"
# --yes accepts the project link prompts non-interactively after `vercel link`
vercel --prod --yes --cwd "$HERE/.."
