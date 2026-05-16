#!/bin/bash
#
# build.sh - assemble an unsigned macOS .pkg installer.
#
# Two-stage build:
#   1. pkgbuild   — wraps the (empty) payload + postinstall script into a
#                   component .pkg called claude-installer-payload.pkg
#   2. productbuild — wraps the component pkg with Distribution.xml + resources
#                   into the final user-facing ClaudeCode-Installer.pkg
#
# We deliberately keep the payload empty: all the actual install work runs
# in the postinstall script (downloads Node, runs npm, etc). This keeps the
# .pkg under 1 MB to ship — the advertised "98 MB" includes Node.js + claude
# which the postinstall fetches on demand.
#
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
DIST="$HERE/dist"
BUILD="$HERE/build"
VERSION="${VERSION:-1.0.0}"
IDENTIFIER="team.dotio.claude-installer"
PRODUCT_NAME="ClaudeCode-Installer.pkg"

rm -rf "$DIST" "$BUILD"
mkdir -p "$DIST" "$BUILD/payload"

# Make sure the postinstall script is executable. pkgbuild requires this.
chmod 0755 "$HERE/scripts/postinstall"

echo "==> pkgbuild: wrapping postinstall into component pkg"
pkgbuild \
  --root "$BUILD/payload" \
  --scripts "$HERE/scripts" \
  --identifier "$IDENTIFIER" \
  --version "$VERSION" \
  --install-location "/" \
  "$BUILD/claude-installer-payload.pkg"

echo "==> productbuild: wrapping with installer UI"
productbuild \
  --distribution "$HERE/Distribution.xml" \
  --resources "$HERE/resources" \
  --package-path "$BUILD" \
  --version "$VERSION" \
  "$DIST/$PRODUCT_NAME"

echo
echo "==> built: $DIST/$PRODUCT_NAME ($(du -h "$DIST/$PRODUCT_NAME" | cut -f1))"
echo "    Test locally:  sudo installer -pkg $DIST/$PRODUCT_NAME -target /"
echo "    Or double-click to open in macOS Installer."

# Clean intermediate build, keep dist
rm -rf "$BUILD"
