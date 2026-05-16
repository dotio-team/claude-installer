#!/bin/bash
#
# deploy-release.sh — publish installer binaries as a GitHub Release.
#
# Usage:
#   VERSION=1.0.0 bash scripts/deploy-release.sh
#
# Picks up whichever artifacts exist locally; CI fills in the rest:
#   installer/macos/dist/ClaudeCode-Installer.pkg   (built on macOS)
#   installer/windows/dist/ClaudeCode-Installer.exe (built on Windows / CI)
#
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE/.."

VERSION="${VERSION:-}"
[ -n "$VERSION" ] || { echo "VERSION env required (e.g. VERSION=1.0.0)"; exit 1; }
TAG="v${VERSION#v}"

# Prefer Homebrew gh over node-gh shim (the latter is a different unrelated tool).
GH="$(command -v /opt/homebrew/bin/gh || command -v gh)"
[ -x "$GH" ] || { echo "gh CLI not found"; exit 1; }

MAC_PKG="$ROOT/installer/macos/dist/ClaudeCode-Installer.pkg"
WIN_EXE="$ROOT/installer/windows/dist/ClaudeCode-Installer.exe"
ASSETS=()
[ -f "$MAC_PKG" ] && ASSETS+=("$MAC_PKG")
[ -f "$WIN_EXE" ] && ASSETS+=("$WIN_EXE")
[ "${#ASSETS[@]}" -gt 0 ] || { echo "no installer artifacts found to upload"; exit 1; }

cd "$ROOT"

# Make sure the tag exists and is pushed before we create a release on it.
if ! git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "==> creating tag $TAG"
  git tag -a "$TAG" -m "Release $TAG"
fi
echo "==> pushing tag $TAG"
git push origin "$TAG" 2>/dev/null || true

NOTES_FILE="$(mktemp)"
trap 'rm -f "$NOTES_FILE"' EXIT
cat > "$NOTES_FILE" <<EOF
Claude Code 원클릭 인스톨러 $TAG

다운로드:
- macOS: \`ClaudeCode-Installer.pkg\`
- Windows: \`ClaudeCode-Installer.exe\`

설치 방법과 보안 경고 우회는 https://claude-installer-psi.vercel.app 에서 안내합니다.
EOF

if "$GH" release view "$TAG" >/dev/null 2>&1; then
  echo "==> release $TAG exists — uploading/replacing assets"
  "$GH" release upload "$TAG" "${ASSETS[@]}" --clobber
else
  echo "==> creating release $TAG"
  "$GH" release create "$TAG" "${ASSETS[@]}" \
    --title "$TAG" \
    --notes-file "$NOTES_FILE" \
    --latest
fi

echo
echo "  Latest URL pattern (always points at the newest release):"
echo "    https://github.com/dotio-team/claude-installer/releases/latest/download/ClaudeCode-Installer.pkg"
echo "    https://github.com/dotio-team/claude-installer/releases/latest/download/ClaudeCode-Installer.exe"
