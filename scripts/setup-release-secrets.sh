#!/usr/bin/env bash
# One-time setup: stores the secrets the Release workflow needs in this repo's GitHub settings.
# Needs: the Developer ID .p12 you exported from Xcode, and an App Store Connect API key (.p8).
# See docs/releasing.md for where to get each one.
set -euo pipefail

repo=$(gh repo view --json nameWithOwner -q .nameWithOwner)
sparkle_version=2.10.1
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

echo "Setting release secrets for $repo"
echo

# 1. Developer ID certificate
read -rp "Path to your Developer ID Application .p12: " p12
p12=${p12/#\~/$HOME}
read -rsp "Its export password: " p12_password
echo
team=$(openssl pkcs12 -in "$p12" -passin "pass:$p12_password" -nokeys -legacy 2>/dev/null \
  | openssl x509 -noout -subject 2>/dev/null | sed -nE 's/.*OU ?= ?([A-Z0-9]{10}).*/\1/p' || true)
if [[ -z $team ]]; then
  read -rp "Couldn't read the team ID from the certificate. Apple team ID (10 characters): " team
fi
base64 -i "$p12" | gh secret set DEVELOPER_ID_P12_BASE64 -R "$repo"
gh secret set DEVELOPER_ID_P12_PASSWORD -R "$repo" --body "$p12_password"
gh secret set APPLE_TEAM_ID -R "$repo" --body "$team"
echo "Certificate stored (team $team)."
echo

# 2. Notarization API key
read -rp "Path to your App Store Connect API key (AuthKey_XXXXXXXXXX.p8): " p8
p8=${p8/#\~/$HOME}
default_id=$(basename "$p8" .p8 | sed -nE 's/^AuthKey_([A-Z0-9]+)$/\1/p')
read -rp "Key ID${default_id:+ [$default_id]}: " key_id
key_id=${key_id:-$default_id}
read -rp "Issuer ID (UUID at the top of the Keys page): " issuer
gh secret set NOTARY_KEY_P8 -R "$repo" < "$p8"
gh secret set NOTARY_KEY_ID -R "$repo" --body "$key_id"
gh secret set NOTARY_ISSUER_ID -R "$repo" --body "$issuer"
echo "Notarization key stored."
echo

# 3. Sparkle update-signing key (kept in your login keychain; reused if it already exists)
echo "Fetching Sparkle $sparkle_version tools to create the update-signing key..."
gh release download "$sparkle_version" -R sparkle-project/Sparkle -p "Sparkle-$sparkle_version.tar.xz" -O - \
  | tar -xJ -C "$tmp"
"$tmp/bin/generate_keys" --account "$repo" > /dev/null
public_key=$("$tmp/bin/generate_keys" --account "$repo" -p)
"$tmp/bin/generate_keys" --account "$repo" -x "$tmp/sparkle.key"
gh secret set SPARKLE_ED_PRIVATE_KEY -R "$repo" < "$tmp/sparkle.key"
gh variable set SPARKLE_PUBLIC_KEY -R "$repo" --body "$public_key"
echo "Update-signing key stored. The private key also stays in your login keychain as a backup."
echo

echo "Done. The next merge to main publishes a release."
