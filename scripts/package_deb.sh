#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE="${1:-$ROOT/app/build/linux/x64/debug/bundle}"
OUTPUT="${2:-$ROOT/app/build/linux/x64/debug/bundle/drople_1.0.0_amd64.deb}"
PACKAGE="drople"
VERSION="${DROPLE_VERSION:-1.0.0}"
ARCH="${DROPLE_ARCH:-amd64}"

if ! command -v dpkg-deb >/dev/null 2>&1; then
  printf 'Error: dpkg-deb is required (install the dpkg package).\n' >&2
  exit 1
fi

if [[ ! -d "$BUNDLE" || ! -x "$BUNDLE/drople" ]]; then
  printf 'Error: bundle directory or executable not found: %s\n' "$BUNDLE" >&2
  exit 1
fi

if [[ ! -d "$BUNDLE/data" || ! -d "$BUNDLE/lib" ]]; then
  printf 'Error: expected Flutter bundle directories data/ and lib/ in %s\n' "$BUNDLE" >&2
  exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
STAGE="$WORK/package"

install -d "$STAGE/opt/drople" "$STAGE/usr/bin" \
  "$STAGE/usr/share/applications" "$STAGE/usr/share/icons/hicolor/256x256/apps" \
  "$STAGE/DEBIAN"
cp -a "$BUNDLE/." "$STAGE/opt/drople/"
ln -s /opt/drople/drople "$STAGE/usr/bin/drople"

cat > "$STAGE/DEBIAN/control" <<EOF
Package: $PACKAGE
Version: $VERSION
Section: utils
Priority: optional
Architecture: $ARCH
Maintainer: Drople
Description: Offline-first notes and peer-to-peer file transfer
EOF

cat > "$STAGE/usr/share/applications/drople.desktop" <<'EOF'
[Desktop Entry]
Name=Drople
Comment=Offline-first notes and peer-to-peer file transfer
Exec=/opt/drople/drople
Icon=drople
Terminal=false
Type=Application
Categories=Utility;
EOF

if [[ -f "$ROOT/app/assets/logo.png" ]]; then
  install -m 0644 "$ROOT/app/assets/logo.png" \
    "$STAGE/usr/share/icons/hicolor/256x256/apps/drople.png"
fi

install -d "$(dirname "$OUTPUT")"
dpkg-deb --root-owner-group --build "$STAGE" "$OUTPUT"
printf 'Created Debian package: %s\n' "$OUTPUT"
