#!/bin/bash
# Creates a local, self-signed code-signing certificate for ClipStack.
#
# Why this exists: macOS ties Accessibility (and other TCC) permissions to an
# app's code signature. An ad-hoc signature (`codesign --sign -`) gets a fresh
# identity on every build, so every reinstall silently invalidated the
# permission you granted — the System Settings toggle stayed on but no longer
# matched the installed app.
#
# Signing with a fixed certificate makes the designated requirement stable:
#   identifier "local.clipstack.app" and certificate leaf = H"<fixed hash>"
#
# This certificate is local only. It is not a credential for any service, it
# signs nothing but this app, and you can delete it any time:
#   security delete-certificate -c "ClipStack Local Signing"
set -euo pipefail

IDENTITY="ClipStack Local Signing"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
    echo "'$IDENTITY' already exists. Nothing to do."
    exit 0
fi

cat > "$WORK/cs.cnf" <<'CNF'
[ req ]
distinguished_name = dn
x509_extensions    = v3
prompt             = no
[ dn ]
CN = ClipStack Local Signing
[ v3 ]
basicConstraints     = critical,CA:false
keyUsage             = critical,digitalSignature
extendedKeyUsage     = critical,codeSigning
CNF

echo "==> Generating certificate…"
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$WORK/cs.cnf" \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null

# Apple's Security framework can't read OpenSSL 3.x's default PKCS#12 flavour.
echo "==> Packaging…"
openssl pkcs12 -export -out "$WORK/cs.p12" -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -passout pass:clipstack -name "$IDENTITY" \
    -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 2>/dev/null

echo "==> Importing into your login keychain…"
security import "$WORK/cs.p12" -k ~/Library/Keychains/login.keychain-db \
    -P clipstack -T /usr/bin/codesign

echo "==> Done. Rebuild with ./build.sh install, then grant Accessibility once."
echo "    The grant will survive future rebuilds."
