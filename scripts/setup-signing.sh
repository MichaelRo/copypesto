#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Creates the local "Pesto Development" signing identity that `make run` and `make install` sign with, so the Accessibility
# grant and the Keychain "Always Allow" entry survive a rebuild. Run once, through `make setup-signing`.
# `make setup-release-signing` runs it again for the "Pesto Release" identity that signs the unsigned 1.0 disk image.
#
#   PESTO_SIGNING_WIDE=1   let codesign use every signing key in the login keychain without asking (the old behavior)
#
# It changes your login keychain, so it says what it will do and waits before starting.
set -euo pipefail

IDENTITY="${DEV_SIGN_IDENTITY:-Pesto Development}"
KEYCHAIN="${PESTO_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"
WAIT="${PESTO_SETUP_SIGNING_WAIT:-5}"

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
  echo "✓ '$IDENTITY' cert already exists: nothing to do"
  exit 0
fi
if security find-identity -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
  echo "error: a '$IDENTITY' certificate is in your keychain, but macOS does not list it as valid for code signing." >&2
  echo "       Delete it in Keychain Access (the certificate and its key), then run make setup-signing again:" >&2
  echo "       a second one would make codesign ambiguous." >&2
  exit 1
fi

cat <<NOTICE

make ${SETUP_TARGET:-setup-signing} will, in your LOGIN keychain:
  1. create a self-signed code-signing certificate '$IDENTITY' (not a certificate authority), valid for ten years;
  2. trust it for code signing only (macOS asks for your password in a Certificate Trust Settings dialog);
NOTICE
if [ -n "${PESTO_SIGNING_WIDE:-}" ]; then
  echo "  3. let codesign use EVERY signing key in that keychain without asking (PESTO_SIGNING_WIDE is set);"
else
  echo "  3. let codesign use that one key without asking, matched by its label (the other keys in the keychain are not"
  echo "     touched; if the label does not match, the first codesign asks once: choose Always Allow)."
fi
cat <<NOTICE
macOS asks for your login password for the last step. To undo it, delete '$IDENTITY' in Keychain Access.
A new certificate resets the Accessibility grant and the Keychain entry that an older one had earned.
Press Control-C within $WAIT seconds to cancel.
NOTICE
sleep "$WAIT"

if ! openssl version | grep -q "OpenSSL 3"; then
  echo "error: OpenSSL 3 is needed (the system openssl is LibreSSL). Run: brew install openssl@3" >&2
  exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/cert.conf" <<CONF
[req]
distinguished_name=dn
x509_extensions=v3
prompt=no
[dn]
CN=$IDENTITY
[v3]
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
subjectKeyIdentifier=hash
basicConstraints=critical,CA:false
CONF
openssl req -newkey rsa:2048 -nodes -keyout "$tmp/key.pem" -x509 -days 3650 -out "$tmp/cert.pem" \
  -config "$tmp/cert.conf" 2>/dev/null
openssl pkcs12 -export -legacy -name "$IDENTITY" -out "$tmp/dev.p12" -inkey "$tmp/key.pem" -in "$tmp/cert.pem" \
  -passout pass:pestosigning 2>/dev/null

security import "$tmp/dev.p12" -k "$KEYCHAIN" -P "pestosigning" -T /usr/bin/codesign -T /usr/bin/security
security add-trusted-cert -p codeSign -r trustRoot -k "$KEYCHAIN" "$tmp/cert.pem"

echo
echo "Letting codesign use the key without prompting. macOS will ask for your LOGIN password (once)."
if [ -n "${PESTO_SIGNING_WIDE:-}" ]; then
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s "$KEYCHAIN"
else
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -l "$IDENTITY" "$KEYCHAIN" \
    || echo "warning: could not set the partition list for '$IDENTITY'; the first codesign will ask once (Always Allow)."
fi

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
  echo
  echo "✓ '$IDENTITY' signing cert created and trusted for code signing"
  if [ "${SETUP_TARGET:-setup-signing}" = "setup-release-signing" ]; then
    echo "  Back it up now: export it from Keychain Access (File > Export Items, .p12, strong password), encrypted, in two"
    echo "  places that are not this Mac. Lose it and the next release is a different identity. Then run 'make release-unsigned'."
  else
    echo "  Now run 'make run': Accessibility permission and Keychain access will persist across rebuilds."
  fi
else
  echo "error: the certificate was imported, but 'security find-identity -v -p codesigning' does not list it." >&2
  echo "       Check Keychain Access: '$IDENTITY' should be marked trusted for Code Signing." >&2
  exit 1
fi
