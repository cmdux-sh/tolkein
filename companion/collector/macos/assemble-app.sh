#!/bin/bash
# Assemble Tolkeins Collector.app around the prebuilt launcher.
# Compiles with clang only when this Mac's architecture has no prebuilt slice.

set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "assemble-app.sh only runs on macOS." >&2
  exit 1
fi

if [[ $# -ne 1 ]]; then
  echo "usage: assemble-app.sh /path/to/Tolkeins Collector.app" >&2
  exit 1
fi

APP="$1"
case "$APP" in
  *"/Tolkeins Collector.app") ;;
  *)
    echo "refusing to replace ${APP}" >&2
    exit 1
    ;;
esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARCH="$(uname -m)"
PREBUILT=""
case "$ARCH" in
  arm64) PREBUILT="${ROOT}/prebuilt/tolkeins-collector-arm64" ;;
  x86_64) PREBUILT="${ROOT}/prebuilt/tolkeins-collector-x86_64" ;;
esac

rm -rf "$APP"
mkdir -p "${APP}/Contents/MacOS"
cp "${ROOT}/Info.plist" "${APP}/Contents/Info.plist"

if [[ -n "$PREBUILT" && -f "$PREBUILT" ]]; then
  cp "$PREBUILT" "${APP}/Contents/MacOS/tolkeins-collector"
else
  if ! command -v clang >/dev/null 2>&1; then
    echo "No prebuilt launcher for ${ARCH}, and clang is not installed." >&2
    echo "Install Command Line Tools (xcode-select --install) and re-run ./collector/install.sh" >&2
    exit 1
  fi
  clang -Os -mmacosx-version-min=13.0 -o "${APP}/Contents/MacOS/tolkeins-collector" "${ROOT}/tolkeins-collector.c"
fi

chmod 755 "${APP}/Contents/MacOS/tolkeins-collector"
