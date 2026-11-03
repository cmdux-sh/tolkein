#!/bin/bash
# Sign Tolkeins Collector.app with a stable local certificate.
#
# Ad-hoc signatures are a different TCC identity on every rebuild. This script
# creates one self-signed code-signing certificate on the Mac and reuses it.
# The private key stays in ~/.config/tolkeins/codesign (mode 700) and in the
# tolkeins-collector keychain. Nothing here is printed.

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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=keychain-list.sh
source "${SCRIPT_DIR}/keychain-list.sh"

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

xattr -cr "$APP" 2>/dev/null || true

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

codesign --verify --strict --verbose=2 "$APP" >/dev/null
identifier="$(codesign -d -v "$APP" 2>&1 | sed -n 's/^Identifier=//p' | head -n 1)"
designated="$(codesign -d -r- "$APP" 2>&1 | sed -n 's/^designated => //p')"
if [[ "$identifier" != "com.tolkeins.collector" ]]; then
  echo "Signed identifier is '${identifier}', expected com.tolkeins.collector." >&2
  exit 1
fi
if [[ "$designated" != *certificate* ]]; then
  echo "The signature is not tied to the local certificate, so the Chrome grant would not survive a rebuild." >&2
  echo "Designated requirement: ${designated}" >&2
  exit 1
fi

echo "Signed ${APP}."
echo "Bundle id: ${identifier}"
echo "Designated requirement: ${designated}"
