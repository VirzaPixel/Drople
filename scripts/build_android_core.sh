#!/usr/bin/env bash
# Kompilasi drople_core untuk target Android (arm64-v8a, armeabi-v7a, x86_64)
# dan salin ke jniLibs agar di-bundle otomatis oleh APK.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE="${1:-release}"

[ -f "$HOME/.cargo/env" ] && source "$HOME/.cargo/env"

if [ -z "${ANDROID_NDK_HOME:-}" ]; then
  POSSIBLE_NDK="$(ls -d /home/mivi/Android/Sdk/ndk/* /opt/android-sdk/ndk/* 2>/dev/null | sort -V | tail -n 1 || true)"
  if [ -n "$POSSIBLE_NDK" ]; then
    export ANDROID_NDK_HOME="$POSSIBLE_NDK"
    echo "Menggunakan ANDROID_NDK_HOME: $ANDROID_NDK_HOME"
  else
    echo "ERROR: ANDROID_NDK_HOME tidak diset dan tidak ditemukan NDK." >&2
    exit 1
  fi
fi

TARGET_DIR="$ROOT/app/android/app/src/main/jniLibs"
mkdir -p "$TARGET_DIR"

cd "$ROOT/core"

TARGET_FLAG=""
if [ "$PROFILE" = "release" ]; then
  TARGET_FLAG="--release"
fi

echo "Membangun drople_core Android ($PROFILE)..."
cargo ndk -t arm64-v8a -t armeabi-v7a -t x86_64 -o "$TARGET_DIR" build $TARGET_FLAG

# Hapus shared lib perantara internal yang tidak perlu ikut di bundle
find "$TARGET_DIR" -name "libif_watch*.so" -delete 2>/dev/null || true

echo "Kompilasi Android selesai -> $TARGET_DIR"
