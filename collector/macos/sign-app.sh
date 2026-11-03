#!/bin/bash
# Sign Tolkeins Collector.app.
#
# Prefer a valid Apple Development or Developer ID identity so the designated
# requirement stays on a certificate the mini already trusts. Set
# TOLKEINS_SIGN_IDENTITY to force a name from `security find-identity -p codesigning`,
# or "local" to keep the self-signed Tolkeins Collector certificate.
# The local certificate is created only when no Apple identity is selected.
# Its private key stays in ~/.config/tolkeins/codesign and is never printed.
#
# Changing the signing identity changes the designated requirement. The Chrome
# Files & Folders switch must be turned on again for Tolkeins Collector.

set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "sign-app.sh only runs on macOS." >&2
  exit 1
fi

if [[ $# -ne 1 ]]; then
  echo "usage: sign-app.sh /path/to/Tolkeins Collector.app" >&2
  exit 1
fi

APP="$1"
case "$APP" in
  *"/Tolkeins Collector.app") ;;
  *)
    echo "refusing to sign ${APP}" >&2
    exit 1
    ;;
esac

if [[ ! -x "${APP}/Contents/MacOS/tolkeins-collector" ]]; then
  echo "missing helper executable in ${APP}" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COLLECTOR_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=keychain-list.sh
source "${SCRIPT_DIR}/keychain-list.sh"

PYTHON="/usr/bin/python3"
if ! "$PYTHON" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 9) else 1)' >/dev/null 2>&1; then
  PYTHON="$(command -v python3 || true)"
fi
if [[ -z "$PYTHON" ]]; then
  echo "python3 is required to choose a signing identity." >&2
  exit 1
fi

identity_text="$(security find-identity -v -p codesigning 2>/dev/null || true)"
set +e
if [[ -n "${TOLKEINS_SIGN_IDENTITY:-}" ]]; then
  chosen="$(
    printf '%s\n' "$identity_text" | PYTHONPATH="${COLLECTOR_ROOT}" "$PYTHON" -m tolkeins.signing_identity \
      --override "$TOLKEINS_SIGN_IDENTITY"
  )"
else
  chosen="$(
    printf '%s\n' "$identity_text" | PYTHONPATH="${COLLECTOR_ROOT}" "$PYTHON" -m tolkeins.signing_identity
  )"
fi
identity_status=$?
set -e
if [[ "$identity_status" -ne 0 ]]; then
  exit "$identity_status"
fi
chosen="$(printf '%s' "$chosen" | tr -d '\r')"

record_identity() {
  local label="$1"
  local dir="${HOME}/.config/tolkeins/codesign"
  local file="${dir}/active-identity"
  local previous=""
  mkdir -p "$dir"
  chmod 700 "$dir" "${HOME}/.config/tolkeins"
  if [[ -f "$file" ]]; then
    previous="$(tr -d '\r\n' < "$file")"
  fi
  printf '%s\n' "$label" > "$file"
  chmod 644 "$file"
  echo "Signing identity: ${label}"
  if [[ "$previous" != "$label" ]]; then
    echo "This identity is new for Tolkeins Collector."
    echo "Turn Chrome on again under System Settings → Privacy & Security → Files and Folders."
    echo "A different designated requirement does not keep the previous grant."
  fi
}

verify_signature() {
  codesign --verify --strict --verbose=2 "$APP" >/dev/null
  identifier="$(codesign -d -v "$APP" 2>&1 | sed -n 's/^Identifier=//p' | head -n 1)"
  designated="$(codesign -d -r- "$APP" 2>&1 | sed -n 's/^designated => //p')"
  if [[ "$identifier" != "com.tolkeins.collector" ]]; then
    echo "Signed identifier is '${identifier}', expected com.tolkeins.collector." >&2
    exit 1
  fi
  if [[ "$designated" != *certificate* ]]; then
    echo "The signature is not tied to a certificate, so the Chrome grant would not survive a rebuild." >&2
    echo "Designated requirement: ${designated}" >&2
    exit 1
  fi
  echo "Signed ${APP}."
  echo "Bundle id: ${identifier}"
  echo "Designated requirement: ${designated}"
}

xattr -cr "$APP" 2>/dev/null || true

if [[ "$chosen" != "local" ]]; then
  echo "Signing with ${chosen}."
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  if ! codesign --force --sign "$chosen" --timestamp=none "$APP" 2>"${tmp}/codesign.err"; then
    echo "codesign could not use ${chosen}." >&2
    cat "${tmp}/codesign.err" >&2
    echo "Unlock the login keychain and allow codesign to use that identity, then re-run ./collector/install.sh." >&2
    echo "TOLKEINS_SIGN_IDENTITY=local forces the self-signed Tolkeins Collector certificate." >&2
    exit 1
  fi
  verify_signature
  record_identity "$chosen"
  exit 0
fi

OPENSSL="/usr/bin/openssl"
CERT_CN="Tolkeins Collector"
IDENT_DIR="${HOME}/.config/tolkeins/codesign"
PASS_FILE="${IDENT_DIR}/keychain.password"
KEY_FILE="${IDENT_DIR}/key.pem"
CERT_FILE="${IDENT_DIR}/cert.pem"
KEYCHAIN="${HOME}/Library/Keychains/tolkeins-collector.keychain-db"

umask 077
mkdir -p "$IDENT_DIR"
chmod 700 "$IDENT_DIR" "${HOME}/.config/tolkeins"

if [[ ! -f "$PASS_FILE" ]]; then
  printf 't%s\n' "$("$OPENSSL" rand -hex 24)" > "$PASS_FILE"
  chmod 600 "$PASS_FILE"
fi
PASS="$(tr -d '[:space:]' < "$PASS_FILE")"
if [[ -z "$PASS" ]]; then
  echo "The signing keychain password file is empty: ${PASS_FILE}" >&2
  exit 1
fi

tmp="$(mktemp -d)"
chmod 700 "$tmp"
previous_default="$(security default-keychain -d user 2>/dev/null | sed -e 's/^[[:space:]]*"//' -e 's/"[[:space:]]*$//' || true)"

cleanup() {
  rm -rf "$tmp"
  if [[ -n "${previous_default}" ]]; then
    security default-keychain -d user -s "$previous_default" >/dev/null 2>&1 || true
  fi
  if [[ -f "$KEYCHAIN" ]]; then
    security lock-keychain "$KEYCHAIN" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

LOGIN_KEYCHAIN=""
if [[ -f "${HOME}/Library/Keychains/login.keychain-db" ]]; then
  LOGIN_KEYCHAIN="${HOME}/Library/Keychains/login.keychain-db"
elif [[ -f "${HOME}/Library/Keychains/login.keychain" ]]; then
  LOGIN_KEYCHAIN="${HOME}/Library/Keychains/login.keychain"
fi

# Snapshot before create-keychain. That command can drop the login keychain
# from the search list, which would break codesign and the user's other apps.
keychain_snapshot_search_list

if [[ ! -f "$KEYCHAIN" ]]; then
  security create-keychain -p "$PASS" "$KEYCHAIN"
  if [[ ! -f "$KEYCHAIN" ]]; then
    echo "Could not create ${KEYCHAIN}." >&2
    exit 1
  fi
fi
keychain_restore_search_list >/dev/null
if ! security unlock-keychain -p "$PASS" "$KEYCHAIN"; then
  echo "Could not unlock the tolkeins-collector keychain." >&2
  echo "Leave ${IDENT_DIR} in place, or run ./collector/uninstall.sh --purge and install again." >&2
  echo "A new certificate is a new TCC identity, so Chrome must be granted again." >&2
  exit 1
fi
security set-keychain-settings -lut 3600 "$KEYCHAIN" >/dev/null

if [[ -f "$KEY_FILE" && ! -f "$CERT_FILE" ]] || [[ -f "$CERT_FILE" && ! -f "$KEY_FILE" ]]; then
  echo "The signing identity in ${IDENT_DIR} is incomplete. Refusing to mint a replacement." >&2
  echo "Restore the missing file, or run ./collector/uninstall.sh --purge and install again." >&2
  exit 1
fi

if [[ ! -f "$KEY_FILE" || ! -f "$CERT_FILE" ]]; then
  cat > "${tmp}/cert.cnf" <<'EOF'
[ req ]
distinguished_name = dn
x509_extensions = codesign_ext
prompt = no
[ dn ]
CN = Tolkeins Collector
O = Tolkeins
[ codesign_ext ]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:FALSE
EOF
  "$OPENSSL" req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
    -keyout "$KEY_FILE" \
    -out "$CERT_FILE" \
    -config "${tmp}/cert.cnf" \
    -extensions codesign_ext
  chmod 600 "$KEY_FILE"
  chmod 644 "$CERT_FILE"
  echo "Created a local code-signing certificate named ${CERT_CN}."
else
  echo "Reusing the local code-signing certificate named ${CERT_CN}."
fi

"$OPENSSL" pkcs12 -export \
  -inkey "$KEY_FILE" \
  -in "$CERT_FILE" \
  -out "${tmp}/identity.p12" \
  -name "$CERT_CN" \
  -passout "pass:${PASS}"

set +e
security import "${tmp}/identity.p12" -k "$KEYCHAIN" -P "$PASS" -f pkcs12 \
  -T /usr/bin/codesign -T /usr/bin/security >/dev/null
set -e
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PASS" "$KEYCHAIN" >/dev/null 2>&1 || true
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$CERT_FILE" >/dev/null 2>&1 || true

sign_app() {
  codesign --force --sign "$1" --keychain "$KEYCHAIN" --timestamp=none "$APP"
}

if ! sign_app "$CERT_CN" 2>"${tmp}/codesign.err"; then
  hash="$(security find-certificate -c "$CERT_CN" -a -Z "$KEYCHAIN" | awk '/SHA-1 hash:/{print $3; exit}')"
  if [[ -z "$hash" ]] || ! sign_app "$hash" 2>>"${tmp}/codesign.err"; then
    echo "codesign could not use the ${CERT_CN} certificate." >&2
    cat "${tmp}/codesign.err" >&2
    echo "Open Keychain Access, select keychain tolkeins-collector, open ${CERT_CN}," >&2
    echo "set Trust → Code Signing to Always Trust, then re-run ./collector/install.sh." >&2
    exit 1
  fi
fi

verify_signature
record_identity "$CERT_CN"
