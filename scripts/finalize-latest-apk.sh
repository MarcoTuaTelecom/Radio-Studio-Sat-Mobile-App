#!/usr/bin/env bash
set -Eeuo pipefail

REPO="${REPO:-/root/Radio-Studio-Sat-Mobile-App}"
VERSION="${VERSION:-1.0.0}"
BUILD_DIR="${BUILD_DIR:-/root/builds}"
PORTAL_ROOT="${PORTAL_ROOT:-/var/www/studiosat-radio-portal}"
PUBLIC_HOST="${PUBLIC_HOST:-https://www.radio.studiosatweb.com.br}"
APK_PATH="$BUILD_DIR/RadioStudioSat-v${VERSION}.apk"
EAS="npx --yes eas-cli@latest"

ok(){ printf '\nPASS  %s\n' "$*"; }
fail(){ printf '\nFAIL  %s\n' "$*" >&2; exit 1; }

cd "$REPO"
for cmd in node npx python3 curl sha256sum; do command -v "$cmd" >/dev/null 2>&1 || fail "comando ausente: $cmd"; done

$EAS whoami >/dev/null 2>&1 || fail "EAS nao autenticado; rode eas login primeiro"

printf '\n===== 1. LOCALIZANDO ULTIMO BUILD ANDROID CONCLUIDO =====\n'
$EAS build:list --platform android --status finished --limit 1 --json --non-interactive > /tmp/studiosat-latest-build.json

readarray -t BUILD_INFO < <(python3 - <<'PY'
import json
p='/tmp/studiosat-latest-build.json'
data=json.load(open(p,encoding='utf-8'))
if isinstance(data,dict):
    data=data.get('builds') or data.get('data') or [data]
if not data:
    raise SystemExit(2)
b=data[0]
print(b.get('id',''))
print(b.get('status',''))
print(b.get('platform',''))
print(b.get('buildProfile') or b.get('profile') or '')
a=b.get('artifacts') or {}
print(a.get('buildUrl') or a.get('applicationArchiveUrl') or b.get('artifactUrl') or '')
PY
)

BUILD_ID="${BUILD_INFO[0]:-}"
BUILD_STATUS="${BUILD_INFO[1]:-}"
BUILD_PLATFORM="${BUILD_INFO[2]:-}"
BUILD_PROFILE="${BUILD_INFO[3]:-}"
BUILD_URL="${BUILD_INFO[4]:-}"

[[ -n "$BUILD_ID" ]] || fail "nenhum build concluido encontrado"
[[ "$BUILD_PLATFORM" == "ANDROID" || "$BUILD_PLATFORM" == "android" || -z "$BUILD_PLATFORM" ]] || fail "ultimo build nao e Android: $BUILD_PLATFORM"
[[ -n "$BUILD_URL" ]] || fail "URL do APK nao encontrada no build $BUILD_ID"

printf 'BUILD_ID=%s\nBUILD_STATUS=%s\nBUILD_PROFILE=%s\nBUILD_URL=%s\n' "$BUILD_ID" "$BUILD_STATUS" "$BUILD_PROFILE" "$BUILD_URL"
ok "build concluido localizado"

printf '\n===== 2. BAIXANDO APK =====\n'
mkdir -p "$BUILD_DIR"
curl -fL --retry 3 --connect-timeout 15 --max-time 600 "$BUILD_URL" -o "$APK_PATH"
python3 - "$APK_PATH" <<'PY'
import sys,zipfile,os
p=sys.argv[1]
if not zipfile.is_zipfile(p):
    raise SystemExit('arquivo baixado nao e APK/ZIP valido')
print(f'APK_SIZE={os.path.getsize(p)}')
print('APK_ZIP=PASS')
PY
APK_SHA="$(sha256sum "$APK_PATH" | awk '{print $1}')"
echo "APK_SHA256=$APK_SHA"
ok "APK salvo em $APK_PATH"

printf '\n===== 3. PUBLICANDO NO PORTAL =====\n'
if [[ -f "$REPO/scripts/deploy-download-page.sh" && -f "$PORTAL_ROOT/index.html" ]]; then
  VERSION="$VERSION" APK_SOURCE="$APK_PATH" PORTAL_ROOT="$PORTAL_ROOT" PUBLIC_HOST="$PUBLIC_HOST" \
    bash "$REPO/scripts/deploy-download-page.sh"
  ok "APK publicado no portal"
else
  fail "deploy do portal nao encontrado"
fi

printf '\n========================================\n'
printf 'RADIO_STUDIO_SAT_ANDROID=PASS\n'
printf 'BUILD_ID=%s\n' "$BUILD_ID"
printf 'APK=%s\n' "$APK_PATH"
printf 'APK_SHA256=%s\n' "$APK_SHA"
printf 'DOWNLOAD_PAGE=%s/app/\n' "$PUBLIC_HOST"
printf '========================================\n'
