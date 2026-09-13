#!/usr/bin/env bash
set -Eeuo pipefail

REPO="${REPO:-/root/Radio-Studio-Sat-Mobile-App}"
KEY="${KEY:-/root/.ssh/id_ed25519_studiosat_mobile}"
VERSION="${VERSION:-1.1.0}"
PROFILE="${PROFILE:-preview}"
PORTAL_ROOT="${PORTAL_ROOT:-/var/www/studiosat-radio-portal}"
PUBLIC_HOST="${PUBLIC_HOST:-https://www.radio.studiosatweb.com.br}"
BUILD_DIR="${BUILD_DIR:-/root/builds}"
APK="$BUILD_DIR/RadioStudioSat-v${VERSION}.apk"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
LOG="/var/log/studiosat-mobile/build-publish-$STAMP.log"

mkdir -p "$(dirname "$LOG")"
exec > >(tee -a "$LOG") 2>&1

ok(){ printf '\nPASS  %s\n' "$*"; }
fail(){ printf '\nFAIL  %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || fail "execute como root"
[[ -d "$REPO/.git" ]] || fail "repositorio ausente: $REPO"
[[ -f "$KEY" ]] || fail "chave GitHub ausente: $KEY"
cd "$REPO"

export GIT_SSH_COMMAND="ssh -i $KEY -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=accept-new"
git config core.fileMode false
git config core.sshCommand "$GIT_SSH_COMMAND"

printf '\n===== 1. SINCRONIZACAO SEGURA =====\n'
if [[ -n "$(git status --porcelain)" ]]; then
  git stash push -u -m "studiosat-auto-$STAMP"
  echo "LOCAL_STASH=studiosat-auto-$STAMP"
fi
SSH_OUT="$(ssh -i "$KEY" -o IdentitiesOnly=yes -o BatchMode=yes -T git@github.com 2>&1 || true)"
printf '%s\n' "$SSH_OUT"
grep -qi 'successfully authenticated' <<<"$SSH_OUT" || fail "GitHub SSH nao autenticou"
git fetch origin main
git checkout main
git pull --ff-only origin main
HEAD="$(git rev-parse HEAD)"
ok "GitHub sincronizado HEAD=$HEAD"

printf '\n===== 2. VERIFICACAO DO APP NATIVO =====\n'
for marker in \
  "A MÚSICA NOS CONECTA" \
  "Rádio\\nStudio Sat" \
  "TRADUÇÃO" \
  "Nossas Emissoras" \
  "Favoritos" \
  "MediaCarousel" \
  "VuMeter" \
  "shouldPlayInBackground" \
  "setActiveForLockScreen"; do
  grep -Fq "$marker" App.tsx || fail "App.tsx sem marcador obrigatorio: $marker"
done
for id in radioprincipal radiopop radiorock radioclassicas radiocountry; do
  grep -Fq "$id" src/config/stations.ts || fail "emissora ausente: $id"
done
ok "estrutura visual/funcional nativa presente"

printf '\n===== 3. NODE / EXPO / TYPESCRIPT =====\n'
for cmd in node npm npx python3 curl git sha256sum nginx; do command -v "$cmd" >/dev/null 2>&1 || fail "comando ausente: $cmd"; done
NODE_MAJOR="$(node -p 'Number(process.versions.node.split(".")[0])')"
(( NODE_MAJOR >= 22 )) || fail "Node 22+ necessario"
npm install --no-audit --no-fund
npx expo install --check
npx --yes expo-doctor
npm run typecheck
ok "Expo Doctor + TypeScript"

printf '\n===== 4. PREBUILD ANDROID LOCAL =====\n'
rm -rf android
CI=1 NODE_ENV=production npx expo prebuild --no-install --platform android
[[ -x android/gradlew || -f android/gradlew ]] || fail "prebuild nao criou android/gradlew"
rm -rf android
ok "prebuild Android"

printf '\n===== 5. PUBLICANDO WEB/PWA ANTES DO BUILD =====\n'
VERSION="$VERSION" bash scripts/deploy-universal-platforms.sh
ok "web/PWA publicado"

printf '\n===== 6. BUILD APK ANDROID REAL =====\n'
VERSION="$VERSION" BUILD_DIR="$BUILD_DIR" PORTAL_ROOT="$PORTAL_ROOT" PUBLIC_HOST="$PUBLIC_HOST" \
  bash scripts/build-release.sh "$PROFILE"
[[ -f "$APK" ]] || fail "APK final nao encontrado: $APK"
python3 - "$APK" <<'PY'
import sys,zipfile
p=sys.argv[1]
assert zipfile.is_zipfile(p), 'APK invalido'
print('APK_ZIP=PASS')
PY
APK_SHA="$(sha256sum "$APK" | awk '{print $1}')"
APK_SIZE="$(stat -c '%s' "$APK")"
(( APK_SIZE > 10000000 )) || fail "APK pequeno demais: $APK_SIZE"
ok "APK construido size=$APK_SIZE sha256=$APK_SHA"

printf '\n===== 7. REPUBLICANDO INSTALADOR COM APK NOVO =====\n'
VERSION="$VERSION" APK_SOURCE="$APK" PORTAL_ROOT="$PORTAL_ROOT" PUBLIC_HOST="$PUBLIC_HOST" \
  bash scripts/deploy-download-page.sh
VERSION="$VERSION" APK_SOURCE="$APK" PORTAL_ROOT="$PORTAL_ROOT" PUBLIC_HOST="$PUBLIC_HOST" \
  bash scripts/deploy-universal-platforms.sh
ok "instalador e PWA atualizados"

printf '\n===== 8. VALIDACAO HTTP FINAL =====\n'
APP_BODY="$(curl -fsSL --max-time 20 "$PUBLIC_HOST/app/")"
LISTEN_BODY="$(curl -fsSL --max-time 20 "$PUBLIC_HOST/listen/")"
grep -Fq '<title>Instalar Radio Studio Sat</title>' <<<"$APP_BODY" || fail "/app/ incorreto"
grep -Fq '<title>Radio Studio Sat</title>' <<<"$LISTEN_BODY" || fail "/listen/ incorreto"
APK_HEADERS="$(curl -fsSI --max-time 20 "$PUBLIC_HOST/downloads/apps/RadioStudioSat-latest.apk" | tr -d '\r')"
grep -qi '^content-type: application/vnd.android.package-archive' <<<"$APK_HEADERS" || fail "APK publico com MIME incorreto"
REMOTE_LEN="$(awk 'BEGIN{IGNORECASE=1}/^content-length:/{print $2}' <<<"$APK_HEADERS" | tail -1)"
[[ -z "$REMOTE_LEN" || "$REMOTE_LEN" == "$APK_SIZE" ]] || fail "APK publico tamanho diferente local=$APK_SIZE remoto=$REMOTE_LEN"
for id in radioprincipal radiopop radiorock radioclassicas radiocountry; do
  BODY="$(mktemp)"; COOKIE="$(mktemp)"
  CODE="$(curl -ksSL --max-redirs 6 -c "$COOKIE" -b "$COOKIE" -o "$BODY" -w '%{http_code}' "https://radio.studiosatweb.com.br/$id/index.m3u8" || true)"
  [[ "$CODE" == 200 ]] && grep -q '#EXTM3U' "$BODY" || fail "HLS invalido: $id HTTP=$CODE"
  rm -f "$BODY" "$COOKIE"
  echo "PASS  HLS $id"
done
nginx -t
ok "validacao final completa"

printf '\n============================================================\n'
printf 'STUDIOSAT_BUILD_INSTALL=PASS\n'
printf 'HEAD=%s\n' "$HEAD"
printf 'VERSION=%s\n' "$VERSION"
printf 'APK=%s\n' "$APK"
printf 'APK_SIZE=%s\n' "$APK_SIZE"
printf 'APK_SHA256=%s\n' "$APK_SHA"
printf 'INSTALLER=%s/app/\n' "$PUBLIC_HOST"
printf 'WEB_APP=%s/listen/\n' "$PUBLIC_HOST"
printf 'ANDROID=%s/downloads/apps/RadioStudioSat-latest.apk\n' "$PUBLIC_HOST"
printf 'LOG=%s\n' "$LOG"
printf '============================================================\n'
