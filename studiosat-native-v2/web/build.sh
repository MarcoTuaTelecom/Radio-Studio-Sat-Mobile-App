#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

command -v wasm-pack >/dev/null || {
  echo "wasm-pack não encontrado. Execute scripts/bootstrap-linux.sh" >&2
  exit 1
}

rm -rf web/dist web/pkg
wasm-pack build web --target web --release --out-dir pkg

mkdir -p web/dist/pkg
cp web/index.html web/styles.css web/media-bridge.js web/dist/
cp -a web/pkg/. web/dist/pkg/

echo "Portal construído em $ROOT/web/dist"
