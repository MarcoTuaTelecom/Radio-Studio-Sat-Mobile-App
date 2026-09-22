#!/usr/bin/env bash
set -Eeuo pipefail

CHUNK_DIR=".bootstrap/chunks"
ARCHIVE=".bootstrap/studiosat-v2-rebuilt.tar.gz"
EXPECTED="0bab426335ac7e69e8374b9cb7888c716d8fbaa12a55f7a875322f076c18cb19"

for n in 00 01 02 03 04 05; do
  [[ -s "$CHUNK_DIR/$n.b64" ]] || {
    echo "Chunk ausente: $CHUNK_DIR/$n.b64" >&2
    exit 1
  }
done

cat "$CHUNK_DIR"/{00,01,02,03,04,05}.b64 | tr -d '\r\n' | base64 -d > "$ARCHIVE"

ACTUAL="$(sha256sum "$ARCHIVE" | awk '{print $1}')"
[[ "$ACTUAL" = "$EXPECTED" ]] || {
  echo "SHA256 reconstruido invalido: $ACTUAL" >&2
  exit 1
}

tar -tzf "$ARCHIVE" >/dev/null
tar -xzf "$ARCHIVE" -C .

bash studiosat-native-v2/scripts/validate.sh

mkdir -p .github/workflows
cp studiosat-native-v2/.github/workflows/ci.yml .github/workflows/studiosat-native-v2-ci.yml
rm -rf studiosat-native-v2/.github

rm -rf .bootstrap
rm -f scripts/expand-studiosat-v2-bootstrap.sh
rm -f .github/workflows/studiosat-v2-bootstrap.yml

echo "Studio Sat Native V2 expandido, validado e pronto para commit."
