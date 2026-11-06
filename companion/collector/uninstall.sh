#!/bin/bash
# Remove the LaunchAgent, Tolkeins Collector.app, and the installed copy.
# Config, logs, and the signing certificate stay unless you pass --purge.

set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "uninstall.sh only removes the launchd agent on macOS." >&2
  exit 1
fi

LABEL="com.tolkeins.collector"
DOMAIN="gui/$(id -u)"
PLIST="${HOME}/Library/LaunchAgents/${LABEL}.plist"
APP="${HOME}/Applications/Tolkeins Collector.app"
KEYCHAIN="${HOME}/Library/Keychains/tolkeins-collector.keychain-db"

launchctl bootout "${DOMAIN}/${LABEL}" 2>/dev/null || true
rm -f "${PLIST}"
rm -rf "${HOME}/.local/share/tolkeins"
rm -rf "${APP}"

if [[ "${1:-}" == "--purge" ]]; then
  rm -rf "${HOME}/.config/tolkeins"
  if [[ -f "$KEYCHAIN" ]]; then
    security delete-keychain "$KEYCHAIN" >/dev/null 2>&1 || true
  fi
  echo "Removed the LaunchAgent, helper app, installed copy, ${HOME}/.config/tolkeins, and the tolkeins-collector keychain."
  echo "The next install creates a new signing identity. Grant Chrome to Tolkeins Collector again."
else
  echo "Removed the LaunchAgent, helper app, and installed copy."
  echo "Kept ${HOME}/.config/tolkeins (pass --purge to delete the token, subscriptions, and signing identity)."
fi
