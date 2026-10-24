#!/bin/bash
# Install the Tolkeins collector as a per-user LaunchAgent.
# Safe to re-run. Does not overwrite an existing config.env or subscriptions.yaml.

set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "install.sh only installs the launchd agent on macOS." >&2
  exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON3="$(command -v python3 || true)"
if [[ -z "${PYTHON3}" ]]; then
  echo "python3 was not found on PATH." >&2
  exit 1
fi
if ! "${PYTHON3}" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 9) else 1)'; then
  echo "python3 3.9 or newer is required (zoneinfo)." >&2
  exit 1
fi

CONFIG_DIR="${HOME}/.config/tolkeins"
INSTALL_DIR="${HOME}/.local/share/tolkeins"
LOG_DIR="${HOME}/Library/Logs/tolkeins"
AGENTS_DIR="${HOME}/Library/LaunchAgents"
LABEL="com.tolkeins.collector"
PLIST="${AGENTS_DIR}/${LABEL}.plist"
DOMAIN="gui/$(id -u)"

mkdir -p "${CONFIG_DIR}" "${INSTALL_DIR}" "${LOG_DIR}" "${AGENTS_DIR}"
chmod 700 "${CONFIG_DIR}"

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

python3 - "${PLIST}" "${PYTHON3}" "${INSTALL_DIR}" "${CONFIG_DIR}" "${LOG_DIR}" <<'PY'
import html
import pathlib
import sys

destination, python3, install_dir, config_dir, log_dir = sys.argv[1:]

def xml(value: str) -> str:
    return html.escape(value, quote=True)

plist = f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.tolkeins.collector</string>
  <key>ProgramArguments</key>
  <array>
    <string>{xml(python3)}</string>
    <string>-m</string>
    <string>tolkeins</string>
  </array>
  <key>WorkingDirectory</key>
  <string>{xml(config_dir)}</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PYTHONPATH</key>
    <string>{xml(install_dir)}</string>
    <key>TOLKEINS_CONFIG_DIR</key>
    <string>{xml(config_dir)}</string>
  </dict>
  <key>StartInterval</key>
  <integer>600</integer>
  <key>RunAtLoad</key>
  <true/>
  <key>StandardOutPath</key>
  <string>{xml(log_dir)}/collector.log</string>
  <key>StandardErrorPath</key>
  <string>{xml(log_dir)}/collector.err.log</string>
</dict>
</plist>
"""
pathlib.Path(destination).write_text(plist, encoding="utf-8")
PY

launchctl bootout "${DOMAIN}/${LABEL}" 2>/dev/null || true
launchctl bootstrap "${DOMAIN}" "${PLIST}"
launchctl enable "${DOMAIN}/${LABEL}"
launchctl kickstart -k "${DOMAIN}/${LABEL}" || true

echo "Installed ${LABEL}."
echo "Logs: ${LOG_DIR}/collector.err.log"
echo "Manual run: TOLKEINS_CONFIG_DIR='${CONFIG_DIR}' PYTHONPATH='${INSTALL_DIR}' '${PYTHON3}' -m tolkeins --dry-run"
