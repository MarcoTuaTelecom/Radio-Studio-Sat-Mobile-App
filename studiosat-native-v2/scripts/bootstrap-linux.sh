#!/usr/bin/env bash
set -Eeuo pipefail

if ! command -v curl >/dev/null; then
  echo "curl é necessário." >&2
  exit 1
fi

if ! command -v rustup >/dev/null; then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal
fi

source "$HOME/.cargo/env"
rustup update stable
rustup target add wasm32-unknown-unknown

if ! command -v wasm-pack >/dev/null; then
  cargo install wasm-pack --locked
fi

echo "Rust: $(rustc --version)"
echo "Cargo: $(cargo --version)"
echo "wasm-pack: $(wasm-pack --version)"
