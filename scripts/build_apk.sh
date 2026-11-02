#!/usr/bin/env bash
# Build APK release dan simpan dengan nama Drople.apk.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT/app"

flutter build apk --release "$@"

mkdir -p build
cp build/app/outputs/flutter-apk/app-release.apk build/Drople.apk
echo "APK: $ROOT/app/build/Drople.apk"
