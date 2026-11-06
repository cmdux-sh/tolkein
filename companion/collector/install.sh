#!/bin/bash
# Install the Tolkeins collector as a per-user LaunchAgent.
# launchd starts Tolkeins Collector.app. That signed app spawns python, so
# macOS can grant Chrome cookie access to one stable bundle id.
# Safe to re-run. Does not overwrite config.env or subscriptions.yaml.

set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "install.sh only installs the launchd agent on macOS." >&2
  exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PYTHON3=""
if /usr/bin/python3 -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 9) else 1)' >/dev/null 2>&1; then
  PYTHON3="/usr/bin/python3"
else
  PYTHON3="$(command -v python3 || true)"
  if [[ -z "$PYTHON3" ]] || ! "$PYTHON3" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 9) else 1)'; then
    echo "python3 3.9 or newer is required (zoneinfo)." >&2
    exit 1
  fi
fi

CONFIG_DIR="${HOME}/.config/tolkeins"
INSTALL_DIR="${HOME}/.local/share/tolkeins"
LOG_DIR="${HOME}/Library/Logs/tolkeins"
AGENTS_DIR="${HOME}/Library/LaunchAgents"
APP="${HOME}/Applications/Tolkeins Collector.app"
LABEL="com.tolkeins.collector"
PLIST="${AGENTS_DIR}/${LABEL}.plist"
DOMAIN="gui/$(id -u)"

mkdir -p "${CONFIG_DIR}" "${INSTALL_DIR}" "${LOG_DIR}" "${AGENTS_DIR}" "${HOME}/Applications"
chmod 700 "${CONFIG_DIR}"

# Build and sign a staged copy first. If signing fails, the installed app and the
# running agent are left as they were.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
STAGED_APP="${STAGE}/Tolkeins Collector.app"
"${ROOT}/macos/assemble-app.sh" "${STAGED_APP}"
"${ROOT}/macos/sign-app.sh" "${STAGED_APP}"

launchctl bootout "${DOMAIN}/${LABEL}" 2>/dev/null || true

rm -rf "${INSTALL_DIR}/tolkeins"
cp -R "${ROOT}/tolkeins" "${INSTALL_DIR}/tolkeins"

if [[ ! -f "${CONFIG_DIR}/config.env" ]]; then
  cp "${ROOT}/config.env.example" "${CONFIG_DIR}/config.env"
  chmod 600 "${CONFIG_DIR}/config.env"
  echo "Created ${CONFIG_DIR}/config.env. Fill in WORKER_URL and WRITE_TOKEN."
else
  echo "Kept existing ${CONFIG_DIR}/config.env"
fi

if [[ ! -f "${CONFIG_DIR}/subscriptions.yaml" ]]; then
  cp "${ROOT}/subscriptions.example.yaml" "${CONFIG_DIR}/subscriptions.yaml"
  echo "Created ${CONFIG_DIR}/subscriptions.yaml. Edit renewal dates, prices, and the Grok window."
else
  echo "Kept existing ${CONFIG_DIR}/subscriptions.yaml"
fi

rm -rf "${APP}"
mv "${STAGED_APP}" "${APP}"
codesign --verify --strict "${APP}"

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [[ -x "$LSREGISTER" ]]; then
  "$LSREGISTER" -f "$APP" >/dev/null
fi

PYTHONPATH="${INSTALL_DIR}" "${PYTHON3}" -m tolkeins.launch_agent \
  --executable "${APP}/Contents/MacOS/tolkeins-collector" \
  --python "${PYTHON3}" \
  --install-dir "${INSTALL_DIR}" \
  --config-dir "${CONFIG_DIR}" \
  --log-dir "${LOG_DIR}" \
  --output "${PLIST}"

launchctl bootstrap "${DOMAIN}" "${PLIST}"
launchctl enable "${DOMAIN}/${LABEL}"
launchctl kickstart -k "${DOMAIN}/${LABEL}" || true

echo "Installed ${LABEL}."
echo "Program: ${APP}/Contents/MacOS/tolkeins-collector"
echo "Logs: ${LOG_DIR}/collector.err.log"
echo "Grant Chrome once: System Settings → Privacy & Security → Files and Folders → Tolkeins Collector → Chrome."
echo "The switch appears after this first run. Then run ./collector/verify-chrome.sh"
