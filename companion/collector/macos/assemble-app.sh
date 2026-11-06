#!/bin/bash
# Assemble Tolkeins Collector.app around the launcher.
# Compiles tolkeins-collector.c with clang when Command Line Tools are installed, so the
# binary matches the source. The prebuilt slices are the fallback and need macOS 15.

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

# /usr/bin/clang exists even without Command Line Tools and opens an install dialog,
# so ask xcrun whether a real compiler is present.
if xcode-select -p >/dev/null 2>&1 && xcrun --sdk macosx --find clang >/dev/null 2>&1; then
  xcrun --sdk macosx clang -Os -mmacosx-version-min=13.0 -o "${APP}/Contents/MacOS/tolkeins-collector" "${ROOT}/tolkeins-collector.c"
elif [[ -n "$PREBUILT" && -f "$PREBUILT" ]]; then
  major="$(sw_vers -productVersion | cut -d. -f1)"
  if [[ "$major" -lt 15 ]]; then
    echo "The prebuilt launcher needs macOS 15 or newer, and Command Line Tools are not installed." >&2
    echo "Run xcode-select --install, then re-run ./collector/install.sh" >&2
    exit 1
  fi
  cp "$PREBUILT" "${APP}/Contents/MacOS/tolkeins-collector"
else
  echo "No prebuilt launcher for ${ARCH}, and Command Line Tools are not installed." >&2
  echo "Run xcode-select --install, then re-run ./collector/install.sh" >&2
  exit 1
fi

chmod 755 "${APP}/Contents/MacOS/tolkeins-collector"
