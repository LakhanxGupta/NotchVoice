#!/bin/bash
# One-time setup: create a stable self-signed code-signing identity so that
# permissions you grant NotchVoice (especially Accessibility, needed for
# auto-paste) survive rebuilds.
#
# Ad-hoc signing (`codesign --sign -`) gives the app a *new* identity on every
# build, so macOS drops it from the Accessibility list each time. A stable
# certificate keeps the identity constant, so you grant Accessibility once.
#
# Run this once:   bash setup-signing.sh
# Then build normally with build.sh — it picks up the identity automatically.
set -euo pipefail

IDENTITY="NotchVoice Self-Signed"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
    echo "Signing identity '$IDENTITY' already exists — nothing to do."
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "==> Generating a self-signed code-signing certificate…"
openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -days 3650 \
    -subj "/CN=$IDENTITY" \
    -addext "basicConstraints=critical,CA:false" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning"

echo "==> Importing certificate and key into your login keychain…"
# Import the cert and key separately (as PEM). This avoids PKCS#12, whose
# OpenSSL 3 default MAC algorithm macOS's `security` tool refuses to import
# ("MAC verification failed"). The keychain pairs them into a code-signing
# identity once both are present.
security import "$TMP/cert.pem" -k "$KEYCHAIN" \
    -T /usr/bin/codesign -T /usr/bin/security
security import "$TMP/key.pem" -k "$KEYCHAIN" \
    -T /usr/bin/codesign -T /usr/bin/security

echo "==> Trusting the certificate for code signing…"
echo "    (macOS may pop up asking you to authorize this — click Allow / enter your password.)"
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem" || true

echo ""
echo "==> Authorizing codesign to use the private key without prompting."
echo "    Enter your macOS login password (input hidden):"
read -rs LOGIN_PW
security set-key-partition-list -S apple-tool:,apple:,codesign: \
    -s -k "$LOGIN_PW" "$KEYCHAIN" >/dev/null 2>&1 || true
unset LOGIN_PW

echo ""
if security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
    echo "✅ Done. '$IDENTITY' is ready. Now run:  bash build.sh"
    echo "   Then grant Accessibility one final time — it'll stick from now on."
else
    echo "⚠️  Identity not found after setup. Check the output above for errors."
    exit 1
fi
