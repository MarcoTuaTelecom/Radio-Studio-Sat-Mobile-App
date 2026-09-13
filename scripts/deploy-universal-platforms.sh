#!/usr/bin/env bash
set -Eeuo pipefail

REPO="${REPO:-/root/Radio-Studio-Sat-Mobile-App}"
PORTAL_ROOT="${PORTAL_ROOT:-/var/www/studiosat-radio-portal}"
VERSION="${VERSION:-1.0.0}"
PUBLIC_HOST="${PUBLIC_HOST:-https://www.radio.studiosatweb.com.br}"
APK_SOURCE="${APK_SOURCE:-/root/builds/RadioStudioSat-v${VERSION}.apk}"
PWA_SRC="$REPO/web/pwa"
PWA_DEST="$PORTAL_ROOT/listen"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP="/var/backups/studiosat/universal-$TS"

ok(){ printf '\nPASS  %s\n' "$*"; }
fail(){ printf '\nFAIL  %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || fail "execute como root"
[[ -d "$REPO/.git" ]] || fail "repositorio ausente"
[[ -f "$APK_SOURCE" ]] || fail "APK ausente: $APK_SOURCE"
[[ -f "$PWA_SRC/index.html" ]] || fail "PWA ausente"
[[ -f "$PORTAL_ROOT/index.html" ]] || fail "portal root invalido"

mkdir -p "$BACKUP"
[[ -d "$PWA_DEST" ]] && cp -a "$PWA_DEST" "$BACKUP/listen.previous"

printf '\n===== 1. CENTRAL UNIVERSAL /app/ =====\n'
VERSION="$VERSION" APK_SOURCE="$APK_SOURCE" PORTAL_ROOT="$PORTAL_ROOT" PUBLIC_HOST="$PUBLIC_HOST" \
  bash "$REPO/scripts/deploy-download-page.sh"
ok "central universal publicada"

printf '\n===== 2. WEB APP /listen/ =====\n'
rm -rf "$PWA_DEST"
install -d -o root -g root -m 0755 "$PWA_DEST"
cp -a "$PWA_SRC/." "$PWA_DEST/"
find "$PWA_DEST" -type d -exec chmod 0755 {} +
find "$PWA_DEST" -type f -exec chmod 0644 {} +
ok "web app publicado"

printf '\n===== 3. NGINX =====\n'
nginx -t
systemctl reload nginx
sleep 1
ok "nginx recarregado"

printf '\n===== 4. VALIDACAO HTTP =====\n'
APP_BODY="$(curl -ksS --resolve www.radio.studiosatweb.com.br:443:127.0.0.1 "$PUBLIC_HOST/app/")"
grep -q 'CENTRAL OFICIAL DE INSTALAÇÃO' <<<"$APP_BODY" || fail "/app/ nao e a central universal"
ok "/app/ central universal"

PWA_BODY="$(curl -ksS --resolve www.radio.studiosatweb.com.br:443:127.0.0.1 "$PUBLIC_HOST/listen/")"
grep -q 'Studio Sat Principal' <<<"$PWA_BODY" || fail "/listen/ nao e o web app"
ok "/listen/ web app"

MANIFEST_CT="$(curl -ksSI --resolve www.radio.studiosatweb.com.br:443:127.0.0.1 "$PUBLIC_HOST/listen/manifest.webmanifest" | tr -d '\r' | awk 'BEGIN{IGNORECASE=1}/^content-type:/{print $2}' | tail -1)"
[[ -n "$MANIFEST_CT" ]] || fail "manifest sem content-type"
ok "manifest PWA"

APK_HEADERS="$(curl -ksSI --resolve www.radio.studiosatweb.com.br:443:127.0.0.1 "$PUBLIC_HOST/downloads/apps/RadioStudioSat-latest.apk")"
grep -qi '^content-type: application/vnd.android.package-archive' <<<"$APK_HEADERS" || fail "APK latest nao esta sendo entregue corretamente"
ok "APK latest"

printf '\n===== 5. STREAMS =====\n'
for id in radioprincipal radiopop radiorock radioclassicas radiocountry; do
  body="$(curl -ksS --max-time 10 "https://radio.studiosatweb.com.br/$id/index.m3u8" || true)"
  grep -q '#EXTM3U' <<<"$body" || fail "HLS falhou: $id"
  echo "PASS  $id"
done

printf '\n========================================\n'
printf 'STUDIOSAT_UNIVERSAL=PASS\n'
printf 'INSTALLER=%s/app/\n' "$PUBLIC_HOST"
printf 'WEB_APP=%s/listen/\n' "$PUBLIC_HOST"
printf 'ANDROID_APK=%s/downloads/apps/RadioStudioSat-latest.apk\n' "$PUBLIC_HOST"
printf 'IPHONE=WEB_APP_SAFARI_ADD_TO_HOME_SCREEN\n'
printf 'WINDOWS=PWA_EDGE_CHROME\n'
printf 'SMART_TV=WEB_APP_BROWSER_MODE\n'
printf 'NATIVE_IOS=REQUIRES_APPLE_SIGNING_TESTFLIGHT_OR_APP_STORE\n'
printf 'BACKUP=%s\n' "$BACKUP"
printf '========================================\n'
