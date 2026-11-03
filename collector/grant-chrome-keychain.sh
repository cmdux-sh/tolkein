#!/bin/bash
# One-time interactive grant for Chrome's "Chrome Safe Storage" Keychain item.
#
# CodexBar decrypts Chrome cookies with that item. `codexbar usage` is a
# background read and will not show a prompt. `cookie refresh
# --allow-keychain-prompt` is the interactive command, and it has to run in
# Terminal so macOS can display the dialog. Always Allow is stored on
# CodexBarCLI, which is the binary that reads the item for the LaunchAgent too.
#
# This script prints CodexBar's status lines only. It does not print cookies
# or the Safe Storage secret.

set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "grant-chrome-keychain.sh must be run on the Mac mini." >&2
  exit 1
fi

if [[ ! -t 0 || ! -t 1 ]]; then
  echo "Run this in Terminal.app so macOS can show the Keychain prompt." >&2
  echo "  ./collector/grant-chrome-keychain.sh" >&2
  exit 1
fi

CODEXBAR="${CODEXBAR_BIN:-/opt/homebrew/bin/codexbar}"
if [[ ! -x "$CODEXBAR" ]]; then
  echo "CodexBar CLI is not executable at ${CODEXBAR}." >&2
  exit 1
fi

resolve_path() {
  local path="$1"
  local dir
  while [[ -L "$path" ]]; do
    dir="$(cd "$(dirname "$path")" && pwd)"
    path="$(readlink "$path")"
    if [[ "$path" != /* ]]; then
      path="${dir}/${path}"
    fi
  done
  echo "$path"
}

CODEXBAR_REAL="$(resolve_path "$CODEXBAR")"

echo "CodexBar will ask to use the Keychain item \"Chrome Safe Storage\"."
echo "Click Always Allow. Allow Once does not cover the LaunchAgent."
echo "The dialog should name CodexBar. The binary is:"
echo "  ${CODEXBAR_REAL}"
echo "If the dialog names Terminal or python3, click Deny. Then in Keychain Access,"
echo "open login → Chrome Safe Storage → Access Control, add that binary, and save."
echo "Do not reveal the password, and do not choose Allow all applications."
echo

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

filter_status() {
  grep -E -v 'sessionKey=|^Cookie:|eyJ[A-Za-z0-9_-]{20,}' || true
}

status=0
for provider in gemini claudeplatform; do
  echo "Refreshing ${provider}..."
  set +e
  "$CODEXBAR" cookie refresh --provider "$provider" --allow-keychain-prompt --format text \
    >"$tmp/out" 2>"$tmp/err"
  code=$?
  set -e
  filter_status <"$tmp/out"
  filter_status <"$tmp/err" >&2
  if [[ "$code" -ne 0 ]]; then
    status=1
  fi
done

echo
if [[ "$status" -eq 0 ]]; then
  echo "Keychain refresh finished. Run ./collector/verify-chrome.sh"
else
  echo "Keychain refresh did not succeed for every provider. Run ./collector/verify-chrome.sh to see the collector error." >&2
fi
exit "$status"
