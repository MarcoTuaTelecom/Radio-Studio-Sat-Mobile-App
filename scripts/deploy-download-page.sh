#!/usr/bin/env bash
# Radio Studio Sat — instala/atualiza a central pública de instalação.
set -Eeuo pipefail
IFS=$'\n\t'

SELF_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$SELF_DIR/.." && pwd)"
TEMPLATE="${TEMPLATE:-$REPO_DIR/web/download/index.html}"
PORTAL_ROOT="${PORTAL_ROOT:-/var/www/studiosat-radio-portal}"
APP_PATH="${APP_PATH:-app}"
DOWNLOAD_DIR="${DOWNLOAD_DIR:-downloads/apps}"
VERSION="${VERSION:-1.0.0}"
PLAY_STORE_URL="${PLAY_STORE_URL:-}"
APP_STORE_URL="${APP_STORE_URL:-}"
APK_SOURCE="${APK_SOURCE:-${1:-}}"
PUBLIC_HOST="${PUBLIC_HOST:-https://www.radio.studiosatweb.com.br}"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP_ROOT="${BACKUP_ROOT:-/var/backups/studiosat/app-download/$TS}"
MUTATED=0

need(){ command -v "$1" >/dev/null 2>&1 || { echo "FATAL=MISSING_TOOL:$1" >&2; exit 70; }; }
for c in python3 install cp rm mkdir sha256sum date readlink; do need "$c"; done

[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo 'FATAL=RUN_AS_ROOT (use sudo)' >&2; exit 77; }
[[ -f "$TEMPLATE" ]] || { echo "FATAL=TEMPLATE_NOT_FOUND:$TEMPLATE" >&2; exit 66; }
[[ -d "$PORTAL_ROOT" ]] || { echo "FATAL=PORTAL_ROOT_NOT_FOUND:$PORTAL_ROOT" >&2; exit 66; }
[[ -f "$PORTAL_ROOT/index.html" ]] || { echo "FATAL=PORTAL_INDEX_NOT_FOUND:$PORTAL_ROOT/index.html" >&2; exit 66; }
[[ "$APP_PATH" != /* && "$DOWNLOAD_DIR" != /* ]] || { echo 'FATAL=APP_PATH_AND_DOWNLOAD_DIR_MUST_BE_RELATIVE' >&2; exit 64; }
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9._-]+)?$ ]] || { echo "FATAL=INVALID_VERSION:$VERSION" >&2; exit 64; }
if [[ -n "$APK_SOURCE" && ! -f "$APK_SOURCE" ]]; then echo "FATAL=APK_NOT_FOUND:$APK_SOURCE" >&2; exit 66; fi

APP_DIR="$PORTAL_ROOT/$APP_PATH"
PUBLIC_DOWNLOAD_DIR="$PORTAL_ROOT/$DOWNLOAD_DIR"
APK_NAME="RadioStudioSat-v${VERSION}.apk"
APK_DEST="$PUBLIC_DOWNLOAD_DIR/$APK_NAME"
APK_LATEST="$PUBLIC_DOWNLOAD_DIR/RadioStudioSat-latest.apk"

mkdir -p "$BACKUP_ROOT"
rollback(){
  local rc=$?
  if (( rc == 0 || MUTATED == 0 )); then return; fi
  echo "ROLLBACK=START rc=$rc" >&2
  rm -rf "$APP_DIR"
  if [[ -d "$BACKUP_ROOT/app.previous" ]]; then cp -a "$BACKUP_ROOT/app.previous" "$APP_DIR"; fi
  if [[ -f "$BACKUP_ROOT/RadioStudioSat-latest.apk.previous" ]]; then
    install -d -m 0755 "$PUBLIC_DOWNLOAD_DIR"
    cp -a "$BACKUP_ROOT/RadioStudioSat-latest.apk.previous" "$APK_LATEST"
  elif [[ -f "$APK_LATEST" ]]; then
    rm -f "$APK_LATEST"
  fi
  echo "ROLLBACK=DONE backup=$BACKUP_ROOT" >&2
}
trap rollback EXIT

same_file(){
  local src="$1" dst="$2"
  [[ -e "$src" && -e "$dst" ]] || return 1
  [[ "$(readlink -f -- "$src")" == "$(readlink -f -- "$dst")" ]]
}

publish_apk_file(){
  local src="$1" dst="$2"
  if same_file "$src" "$dst"; then
    chmod 0644 "$dst"
    echo "APK_COPY=SKIP_SAME_FILE src=$src dst=$dst"
    return 0
  fi
  install -o root -g root -m 0644 "$src" "$dst"
}

printf 'Radio Studio Sat — deploy da central de instalação\nUTC=%s\nPORTAL_ROOT=%s\nBACKUP=%s\n' "$TS" "$PORTAL_ROOT" "$BACKUP_ROOT"

if [[ -d "$APP_DIR" ]]; then cp -a "$APP_DIR" "$BACKUP_ROOT/app.previous"; fi
if [[ -f "$APK_LATEST" ]]; then cp -a "$APK_LATEST" "$BACKUP_ROOT/RadioStudioSat-latest.apk.previous"; fi
MUTATED=1

install -d -o root -g root -m 0755 "$APP_DIR" "$PUBLIC_DOWNLOAD_DIR"

APK_URL="#apk-pendente"
APK_CLASS="disabled"
APK_DOWNLOAD='aria-disabled="true"'
if [[ -n "$APK_SOURCE" ]]; then
  publish_apk_file "$APK_SOURCE" "$APK_DEST"
  publish_apk_file "$APK_SOURCE" "$APK_LATEST"
  APK_URL="/$DOWNLOAD_DIR/$APK_NAME"
  APK_CLASS=""
  APK_DOWNLOAD="download"
fi

PLAY_CLASS="disabled"; [[ -n "$PLAY_STORE_URL" ]] && PLAY_CLASS="" || PLAY_STORE_URL="#google-play-pendente"
APPLE_CLASS="disabled"; [[ -n "$APP_STORE_URL" ]] && APPLE_CLASS="" || APP_STORE_URL="#app-store-pendente"
YEAR="$(date -u +%Y)"

export TEMPLATE APP_DIR VERSION PLAY_STORE_URL APP_STORE_URL APK_URL APK_CLASS APK_DOWNLOAD PLAY_CLASS APPLE_CLASS YEAR
python3 <<'PY'
import os
from pathlib import Path
src=Path(os.environ['TEMPLATE']).read_text(encoding='utf-8')
values={
 'VERSION':os.environ['VERSION'],'PLAY_STORE_URL':os.environ['PLAY_STORE_URL'],'APP_STORE_URL':os.environ['APP_STORE_URL'],
 'APK_URL':os.environ['APK_URL'],'APK_CLASS':os.environ['APK_CLASS'],'APK_DOWNLOAD':os.environ['APK_DOWNLOAD'],
 'PLAY_CLASS':os.environ['PLAY_CLASS'],'APPLE_CLASS':os.environ['APPLE_CLASS'],'YEAR':os.environ['YEAR'],
}
for key,value in values.items(): src=src.replace('@@'+key+'@@', value)
out=Path(os.environ['APP_DIR'])/'index.html'
out.write_text(src,encoding='utf-8')
PY
chmod 0644 "$APP_DIR/index.html"

grep -q '<title>Instalar Radio Studio Sat</title>' "$APP_DIR/index.html"
grep -q 'CENTRAL OFICIAL DE INSTALAÇÃO' "$APP_DIR/index.html"
! grep -q '@@[A-Z_][A-Z_]*@@' "$APP_DIR/index.html" || { echo 'FATAL=UNRENDERED_TEMPLATE_TOKEN' >&2; exit 65; }
sha256sum "$APP_DIR/index.html" | tee "$BACKUP_ROOT/page.sha256"
if [[ -n "$APK_SOURCE" ]]; then sha256sum "$APK_DEST" "$APK_LATEST" | tee "$BACKUP_ROOT/apk.sha256"; fi

if command -v nginx >/dev/null 2>&1; then nginx -t; fi

trap - EXIT
MUTATED=0
printf '\nRESULT=PASS\nPAGE=%s/%s/\n' "$PUBLIC_HOST" "$APP_PATH"
if [[ -n "$APK_SOURCE" ]]; then printf 'APK=%s/%s/%s\nLATEST_APK=%s/%s/RadioStudioSat-latest.apk\n' "$PUBLIC_HOST" "$DOWNLOAD_DIR" "$APK_NAME" "$PUBLIC_HOST" "$DOWNLOAD_DIR"; else echo 'APK=PENDING'; fi
printf 'BACKUP=%s\n' "$BACKUP_ROOT"
