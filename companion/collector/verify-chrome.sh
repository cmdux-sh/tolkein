#!/bin/bash
# Run one dry-run through Tolkeins Collector.app and print gemini and claudeplatform status.
# Writes no snapshot to the Worker. Prints no tokens, cookies, or config.env values.

set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "verify-chrome.sh must be run on the Mac mini." >&2
  exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="${HOME}/Applications/Tolkeins Collector.app/Contents/MacOS/tolkeins-collector"
PLIST="${HOME}/Library/LaunchAgents/com.tolkeins.collector.plist"

if [[ ! -x "$HELPER" ]]; then
  echo "Missing ${HELPER}." >&2
  echo "From the repo checkout: ./collector/install.sh" >&2
  exit 1
fi

if [[ ! -f "$PLIST" ]]; then
  echo "Missing ${PLIST}. Run ./collector/install.sh" >&2
  exit 1
fi

python3 - "$PLIST" <<'PY'
import sys

text = open(sys.argv[1], encoding="utf-8").read()
program = "Tolkeins Collector.app/Contents/MacOS/tolkeins-collector"
if program not in text:
    sys.exit("LaunchAgent is not Tolkeins Collector.app. Re-run ./collector/install.sh")
if "<string>-m</string>" in text:
    sys.exit("LaunchAgent still runs python -m tolkeins. Re-run ./collector/install.sh")
print("LaunchAgent program is Tolkeins Collector.app")
PY

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

"$HELPER" --dry-run >"$tmp/snapshot.json" 2>"$tmp/stderr.txt" || true

PYTHONPATH="${ROOT}" python3 -m tolkeins.chrome_status \
  --stderr "$tmp/stderr.txt" \
  --snapshot "$tmp/snapshot.json"
