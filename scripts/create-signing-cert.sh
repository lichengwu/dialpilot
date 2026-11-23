#!/bin/sh
# One-time setup: the fixed self-signed certificate that signs every release.
#
#   ./scripts/create-signing-cert.sh
#
# Why self-signed: TCC pins grants to the app's designated requirement. With
# ad-hoc signing that requirement is the binary's cdhash, so every release
# invalidates Input Monitoring / Accessibility. Signing with a *fixed*
# certificate changes the requirement to
#     identifier "dev.lichengwu.dialpilot" and certificate leaf = H"<sha1>"
# which stays identical across releases — grants survive updates. The cert
# does not need to be trusted by anyone (Gatekeeper behaviour is unchanged);
# it only needs to be the SAME certificate every time.
#
# What this creates:
#   - identity "DialPilot Release" in a dedicated keychain
#     ~/Library/Keychains/dialpilot-release.keychain-db (random password,
#     stored 0600 next to it) — usable locally and importable in CI
#   - certs/dialpilot-release.crt  : PUBLIC certificate, committed to the repo
#     so anyone can verify a download was signed by the project key
#   - ~/dialpilot-release-backup.p12 : ENCRYPTED private-key backup.
#     Move it into your password manager, then delete the file. NEVER commit
#     it. If this key is lost, every user must re-grant permissions once.
#
# Idempotent: refuses to run if the identity already exists.
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
IDENTITY_NAME="DialPilot Release"
KEYCHAIN="$HOME/Library/Keychains/dialpilot-release.keychain-db"
KEYCHAIN_PASS_FILE="$HOME/.dialpilot-release-keychain.pass"
BACKUP_P12="$HOME/dialpilot-release-backup.p12"
CERT_OUT="$PROJECT_DIR/certs/dialpilot-release.crt"

if security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null | grep -q "$IDENTITY_NAME"; then
    echo "Identity '$IDENTITY_NAME' already exists in $KEYCHAIN — nothing to do." >&2
    echo "To rotate it on purpose, delete the keychain first (users re-grant once)." >&2
    exit 1
fi
command -v openssl >/dev/null || { echo "openssl is required" >&2; exit 1; }

umask 077
WORK=$(mktemp -d)
cleanup() { rm -rf -- "$WORK"; }
trap cleanup EXIT HUP INT TERM

# The three extensions are all mandatory: codesign reports "no identity
# found" for a cert missing keyUsage=digitalSignature, and a CA cert is
# rejected outright. 20 years: rotating the cert costs every user a re-grant.
openssl req -x509 -newkey rsa:2048 -days 7300 -nodes \
    -keyout "$WORK/release.key" -out "$WORK/release.crt" \
    -subj "/CN=$IDENTITY_NAME" \
    -addext "basicConstraints=critical,CA:FALSE" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=codeSigning" 2>/dev/null

# macOS keychain cannot import OpenSSL 3's default AES-256 PKCS#12; -legacy
# emits the RC2/3DES format it understands. Empty passwords also fail.
P12_PASS=$(openssl rand -hex 16)
openssl pkcs12 -export -legacy \
    -in "$WORK/release.crt" -inkey "$WORK/release.key" \
    -out "$WORK/release.p12" -password "pass:$P12_PASS" \
    -name "$IDENTITY_NAME" 2>/dev/null

KC_PASS=$(openssl rand -hex 24)
printf '%s' "$KC_PASS" > "$KEYCHAIN_PASS_FILE"
security create-keychain -p "$KC_PASS" "$KEYCHAIN"
security set-keychain-settings "$KEYCHAIN"          # no auto-lock
security unlock-keychain -p "$KC_PASS" "$KEYCHAIN"
security import "$WORK/release.p12" -k "$KEYCHAIN" -P "$P12_PASS" \
    -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: \
    -s -k "$KC_PASS" "$KEYCHAIN" >/dev/null 2>&1

# Keep the login keychain first in the user search list, ours appended.
LOGIN="$HOME/Library/Keychains/login.keychain-db"
security list-keychains -d user -s "$LOGIN" "$KEYCHAIN"

mkdir -p "$PROJECT_DIR/certs"
cp "$WORK/release.crt" "$CERT_OUT"

# Encrypted backup for the password manager (and for the CI secret).
cp "$WORK/release.p12" "$BACKUP_P12"
printf '%s' "$P12_PASS" > "$BACKUP_P12.pass"
chmod 600 "$BACKUP_P12" "$BACKUP_P12.pass"

echo "identity:  $IDENTITY_NAME"
echo "keychain:  $KEYCHAIN (password: $KEYCHAIN_PASS_FILE)"
echo "public:    $CERT_OUT  (commit this)"
echo "fingerprint (sha1):"
openssl x509 -in "$CERT_OUT" -noout -fingerprint -sha1 | sed 's/^/  /'
echo
echo "PRIVATE backup (move to your password manager, then delete both files):"
echo "  $BACKUP_P12"
echo "  $BACKUP_P12.pass"
echo
echo "CI setup (mode 2 — contributors never hold the key):"
echo "  base64 -i $BACKUP_P12 | gh secret set DIALPILOT_SIGNING_P12 -R lichengwu/dialpilot"
echo "  gh secret set DIALPILOT_P12_PASSWORD -R lichengwu/dialpilot  # paste contents of .pass"
