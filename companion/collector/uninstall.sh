#!/bin/bash
# Remove the LaunchAgent and the installed copy.
# Config and logs stay unless you pass --purge.

set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "uninstall.sh only removes the launchd agent on macOS." >&2
  exit 1
fi

LABEL="com.tolkeins.collector"
DOMAIN="gui/$(id -u)"
PLIST="${HOME}/Library/LaunchAgents/${LABEL}.plist"

launchctl bootout "${DOMAIN}/${LABEL}" 2>/dev/null || true
rm -f "${PLIST}"
rm -rf "${HOME}/.local/share/tolkeins"

if [[ "${1:-}" == "--purge" ]]; then
  rm -rf "${HOME}/.config/tolkeins"
  echo "Removed the LaunchAgent, installed copy, and ${HOME}/.config/tolkeins"
else
  echo "Removed the LaunchAgent and installed copy."
  echo "Kept ${HOME}/.config/tolkeins (pass --purge to delete the token and subscriptions)."
fi
