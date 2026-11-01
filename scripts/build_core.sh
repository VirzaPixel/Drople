#!/usr/bin/env bash
# Build Rust core dan salin lib ke app/native/ agar bisa dipakai Flutter.
# Pemakaian: scripts/build_core.sh [release|debug]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE="${1:-release}"

# shellcheck disable=SC1091
[ -f "$HOME/.cargo/env" ] && source "$HOME/.cargo/env"

cd "$ROOT/core"

case "$(uname -s)" in
  Linux*)   LIB_NAME="libdrople_core.so" ;;
  Darwin*)  LIB_NAME="libdrople_core.dylib" ;;
  MINGW*|MSYS*|CYGWIN*) LIB_NAME="drople_core.dll" ;;
  *)        LIB_NAME="libdrople_core.so" ;;
esac

if [ "$PROFILE" = "debug" ]; then
  cargo build
  SRC="$ROOT/core/target/debug/$LIB_NAME"
else
  cargo build --release
  SRC="$ROOT/core/target/release/$LIB_NAME"
fi

DEST="$ROOT/app/native"
mkdir -p "$DEST"
cp "$SRC" "$DEST/$LIB_NAME"

echo "drople_core ($PROFILE) -> $DEST/$LIB_NAME"
