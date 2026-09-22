#!/usr/bin/env bash
set -Eeuo pipefail

ARCHIVE=".bootstrap/studiosat-v2-v0.1.0.tar.gz"
EXPECTED="cbf3d964efdfed86d9826f0ba458beeb78dce4ddb698849a81c741bf0d9485b5"

[[ -f "$ARCHIVE" ]] || { echo "Archive ausente"; exit 1; }

ACTUAL="$(sha256sum "$ARCHIVE" | awk '{print $1}')"
[[ "$ACTUAL" = "$EXPECTED" ]] || {
  echo "SHA256 invalido: $ACTUAL" >&2
  exit 1
}

tar -tzf "$ARCHIVE" >/dev/null
tar -xzf "$ARCHIVE" -C .

bash studiosat-native-v2/scripts/validate.sh

mkdir -p .github/workflows
cp studiosat-native-v2/.github/workflows/ci.yml .github/workflows/studiosat-native-v2-ci.yml
rm -rf studiosat-native-v2/.github

rm -f "$ARCHIVE"
rmdir .bootstrap 2>/dev/null || true
rm -f scripts/expand-studiosat-v2-bootstrap.sh
rm -f .github/workflows/studiosat-v2-bootstrap.yml

echo "Studio Sat Native V2 expandido e validado."
