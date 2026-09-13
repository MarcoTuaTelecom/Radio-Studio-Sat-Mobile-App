#!/usr/bin/env bash
set -Eeuo pipefail

PROFILE="${1:-preview}"
REPO="${REPO:-/root/Radio-Studio-Sat-Mobile-App}"
VERSION="${VERSION:-1.0.0}"
BUILD_DIR="${BUILD_DIR:-/root/builds}"
PORTAL_ROOT="${PORTAL_ROOT:-/var/www/studiosat-radio-portal}"
PUBLIC_HOST="${PUBLIC_HOST:-https://www.radio.studiosatweb.com.br}"
APK_PATH="$BUILD_DIR/RadioStudioSat-v${VERSION}.apk"
EAS="npx --yes eas-cli@latest"

ok(){ printf '\nPASS  %s\n' "$*"; }
fail(){ printf '\nFAIL  %s\n' "$*" >&2; exit 1; }

[[ -d "$REPO" ]] || fail "repositorio ausente: $REPO"
cd "$REPO"

for cmd in node npm npx python3 curl git sha256sum; do
  command -v "$cmd" >/dev/null 2>&1 || fail "comando ausente: $cmd"
done

NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]')"
NODE_MINOR="$(node -p 'process.versions.node.split(".")[1]')"
if (( NODE_MAJOR < 22 || (NODE_MAJOR == 22 && NODE_MINOR < 13) )); then
  fail "Node.js 22.13+ necessario; encontrado $(node -v)"
fi
ok "Node $(node -v) / npm $(npm -v)"

printf '\n===== 0. ASSETS NATIVOS =====\n'
[[ -f scripts/generate-assets.mjs ]] || fail "scripts/generate-assets.mjs ausente"
node scripts/generate-assets.mjs
ok "assets PNG validos preparados"

printf '\n===== 1. DEPENDENCIAS EXPO SDK 57 =====\n'
npm install --no-audit --no-fund
npx expo install --fix
ok "dependencias instaladas e alinhadas"

printf '\n===== 2. EXPO DOCTOR =====\n'
npx --yes expo-doctor
ok "expo-doctor"

printf '\n===== 3. TYPESCRIPT =====\n'
npm run typecheck
ok "typecheck"

printf '\n===== 4. AUTENTICACAO EXPO / EAS =====\n'
if ! $EAS whoami >/tmp/studiosat-eas-whoami.txt 2>&1; then
  echo "Login Expo necessario. Como este servidor e remoto/headless, o login sera feito no proprio terminal."
  $EAS login --no-browser
fi
EAS_USER="$($EAS whoami | tail -n 1 | tr -d '\r')"
ok "EAS autenticado: $EAS_USER"

printf '\n===== 5. PROJETO EAS =====\n'
PROJECT_ID="$(python3 - <<'PY'
import json
try:
    data=json.load(open('app.json',encoding='utf-8'))
    print(data.get('expo',{}).get('extra',{}).get('eas',{}).get('projectId',''))
except Exception:
    print('')
PY
)"

if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "REPLACE_AFTER_EAS_INIT" ]]; then
  echo "O projeto ainda nao esta vinculado ao EAS. Criando/vinculando agora..."
  $EAS init
  PROJECT_ID="$(python3 - <<'PY'
import json
try:
    data=json.load(open('app.json',encoding='utf-8'))
    print(data.get('expo',{}).get('extra',{}).get('eas',{}).get('projectId',''))
except Exception:
    print('')
PY
)"
fi
[[ -n "$PROJECT_ID" && "$PROJECT_ID" != "REPLACE_AFTER_EAS_INIT" ]] || fail "EAS projectId nao foi configurado"
ok "EAS projectId: $PROJECT_ID"

printf '\n===== 6. VALIDACAO FINAL ANTES DO BUILD =====\n'
npx --yes expo-doctor
npm run typecheck
ok "fonte pronto para build"

printf '\n===== 6B. PREBUILD ANDROID LOCAL =====\n'
rm -rf android
CI=1 NODE_ENV=production npx expo prebuild --no-install --platform android
[[ -f android/gradlew ]] || fail "prebuild Android nao criou android/gradlew"
ok "prebuild Android local"
rm -rf android

printf '\n===== 7. BUILD ANDROID APK (%s) =====\n' "$PROFILE"
NODE_ENV=production $EAS build --platform android --profile "$PROFILE" --wait --non-interactive
ok "EAS Build terminou"

printf '\n===== 8. LOCALIZANDO APK =====\n'
mkdir -p "$BUILD_DIR"
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
a=b.get('artifacts') or {}
print(a.get('buildUrl') or a.get('applicationArchiveUrl') or b.get('artifactUrl') or '')
print(b.get('status',''))
PY
)

BUILD_ID="${BUILD_INFO[0]:-}"
BUILD_URL="${BUILD_INFO[1]:-}"
BUILD_STATUS="${BUILD_INFO[2]:-}"
[[ -n "$BUILD_ID" ]] || fail "nao consegui identificar o build EAS"
[[ -n "$BUILD_URL" ]] || fail "build concluido, mas URL do APK nao foi encontrada"

printf 'BUILD_ID=%s\nBUILD_STATUS=%s\nBUILD_URL=%s\n' "$BUILD_ID" "$BUILD_STATUS" "$BUILD_URL"

curl -fL --retry 3 --connect-timeout 15 --max-time 600 "$BUILD_URL" -o "$APK_PATH"
python3 - "$APK_PATH" <<'PY'
import sys, zipfile
p=sys.argv[1]
if not zipfile.is_zipfile(p):
    raise SystemExit('arquivo baixado nao e um APK/ZIP valido')
print('APK_ZIP=PASS')
PY
APK_SHA="$(sha256sum "$APK_PATH" | awk '{print $1}')"
ok "APK baixado: $APK_PATH"
echo "APK_SHA256=$APK_SHA"

printf '\n===== 9. PUBLICACAO DA PAGINA DE DOWNLOAD =====\n'
if [[ -f "$REPO/scripts/deploy-download-page.sh" && -f "$PORTAL_ROOT/index.html" ]]; then
  VERSION="$VERSION" APK_SOURCE="$APK_PATH" PORTAL_ROOT="$PORTAL_ROOT" PUBLIC_HOST="$PUBLIC_HOST" \
    bash "$REPO/scripts/deploy-download-page.sh"
  ok "APK publicado na pagina de download"
else
  echo "WARN  portal/deploy nao encontrado; APK permaneceu apenas em $APK_PATH"
fi

printf '\n========================================\n'
printf 'RADIO_STUDIO_SAT_ANDROID=PASS\n'
printf 'VERSION=%s\n' "$VERSION"
printf 'EAS_PROJECT_ID=%s\n' "$PROJECT_ID"
printf 'BUILD_ID=%s\n' "$BUILD_ID"
printf 'APK=%s\n' "$APK_PATH"
printf 'APK_SHA256=%s\n' "$APK_SHA"
printf 'DOWNLOAD_PAGE=%s/app/\n' "$PUBLIC_HOST"
printf '========================================\n'
