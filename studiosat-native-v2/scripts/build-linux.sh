#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

source "$HOME/.cargo/env" 2>/dev/null || true

cargo fmt --all -- --check
cargo check -p studiosat-core
cargo check -p studiosat-api
cargo check -p studiosat-web --target wasm32-unknown-unknown
cargo build --release -p studiosat-api

bash web/build.sh

mkdir -p dist/api dist/web
cp target/release/studiosat-api dist/api/
cp -a web/dist/. dist/web/

echo "Build final:"
find dist -maxdepth 3 -type f -printf '%p\n' | sort
