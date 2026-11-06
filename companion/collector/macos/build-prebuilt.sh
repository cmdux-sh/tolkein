#!/bin/bash
# Rebuild the committed Mach-O launchers from tolkeins-collector.c.
# The Mac mini does not need this. install.sh copies the committed slices
# and signs them with the local certificate.
#
# Usage, from a machine with zig:
#   ZIG=/path/to/zig ./collector/macos/build-prebuilt.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZIG="${ZIG:-zig}"
mkdir -p "${ROOT}/prebuilt"

"$ZIG" cc -target aarch64-macos -mmacosx-version-min=13.0 -O2 \
  -o "${ROOT}/prebuilt/tolkeins-collector-arm64" \
  "${ROOT}/tolkeins-collector.c"
"$ZIG" cc -target x86_64-macos -mmacosx-version-min=13.0 -O2 \
  -o "${ROOT}/prebuilt/tolkeins-collector-x86_64" \
  "${ROOT}/tolkeins-collector.c"
