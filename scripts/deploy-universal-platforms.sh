#!/usr/bin/env bash
set -Eeuo pipefail

REPO="${REPO:-/root/Radio-Studio-Sat-Mobile-App}"
PORTAL_ROOT="${PORTAL_ROOT:-/var/www/studiosat-radio-portal}"
VERSION="${VERSION:-1.0.0}"
PUBLIC_HOST="${PUBLIC_HOST:-https://www.radio.studiosatweb.com.br}"
PUBLIC_DOMAIN="www.radio.studiosatweb.com.br"
STREAM_DOMAIN="radio.studiosatweb.com.br"
APK_SOURCE="${APK_SOURCE:-/root/builds/RadioStudioSat-v${VERSION}.apk}"
PWA_SRC="$REPO/web/pwa"
PWA_DEST="$PORTAL_ROOT/listen"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP="/var/backups/studiosat/universal-$TS"

ok(){ printf '\nPASS  %s\n' "$*"; }
fail(){ printf '\nFAIL  %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || fail "execute como root"
for cmd in bash python3 curl nginx systemctl git; do command -v "$cmd" >/dev/null 2>&1 || fail "comando ausente: $cmd"; done
[[ -d "$REPO/.git" ]] || fail "repositorio ausente"
[[ -f "$APK_SOURCE" ]] || fail "APK ausente: $APK_SOURCE"
[[ -f "$PWA_SRC/index.html" ]] || fail "PWA ausente"
[[ -f "$PWA_SRC/manifest.webmanifest" ]] || fail "manifest PWA ausente"
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
python3 "$REPO/scripts/generate-pwa-icons.py" "$PWA_DEST"
find "$PWA_DEST" -type d -exec chmod 0755 {} +
find "$PWA_DEST" -type f -exec chmod 0644 {} +
python3 - "$PWA_DEST/manifest.webmanifest" <<'PY'
import json,sys
p=sys.argv[1]
d=json.load(open(p,encoding='utf-8'))
assert d['start_url']=='/listen/'
assert d['scope']=='/listen/'
assert d['display'] in ('standalone','fullscreen','minimal-ui')
sizes={x.get('sizes') for x in d.get('icons',[])}
assert '192x192' in sizes and '512x512' in sizes
print('MANIFEST_JSON=PASS')
PY
ok "web app e manifest preparados"

printf '\n===== 3. ROTAS EXPLICITAS NGINX =====\n'
[[ -f "$REPO/scripts/fix-universal-routing.sh" ]] || fail "fix-universal-routing.sh ausente"
PORTAL_ROOT="$PORTAL_ROOT" HOST="$PUBLIC_DOMAIN" bash "$REPO/scripts/fix-universal-routing.sh"
ok "rotas /app/ e /listen/"

printf '\n===== 4. CORS DOS STREAMS HLS =====\n'
[[ -f "$REPO/scripts/fix-hls-cors.sh" ]] || fail "fix-hls-cors.sh ausente"
HOST="$STREAM_DOMAIN" ORIGIN="$PUBLIC_HOST" bash "$REPO/scripts/fix-hls-cors.sh"
ok "HLS liberado para o Web App"

printf '\n===== 5. NGINX FINAL =====\n'
nginx -t
systemctl reload nginx
sleep 1
ok "nginx valido e recarregado"

printf '\n===== 6. VALIDACAO LOCAL /app/ =====\n'
APP_HEADERS="$(curl -ksSI --resolve "$PUBLIC_DOMAIN:443:127.0.0.1" "$PUBLIC_HOST/app/")"
APP_BODY="$(curl -ksS --resolve "$PUBLIC_DOMAIN:443:127.0.0.1" "$PUBLIC_HOST/app/")"
printf '%s\n' "$APP_HEADERS"
grep -q '<title>Instalar Radio Studio Sat</title>' <<<"$APP_BODY" || fail "/app/ nao entrega central universal"
grep -q 'Windows detectado' <<<"$APP_BODY" || fail "/app/ sem detector Windows"
grep -q 'iPhone / iPad detectado' <<<"$APP_BODY" || fail "/app/ sem detector iPhone"
ok "/app/ central universal real"

printf '\n===== 7. VALIDACAO LOCAL /listen/ PWA =====\n'
PWA_HEADERS="$(curl -ksSI --resolve "$PUBLIC_DOMAIN:443:127.0.0.1" "$PUBLIC_HOST/listen/")"
PWA_BODY="$(curl -ksS --resolve "$PUBLIC_DOMAIN:443:127.0.0.1" "$PUBLIC_HOST/listen/")"
printf '%s\n' "$PWA_HEADERS"
grep -q '<title>Radio Studio Sat</title>' <<<"$PWA_BODY" || fail "/listen/ nao entrega Web App"
grep -q 'hls.js@1.6.13' <<<"$PWA_BODY" || fail "HLS.js ausente"
grep -q 'beforeinstallprompt' <<<"$PWA_BODY" || fail "instalacao Windows PWA ausente"
grep -q 'apple-mobile-web-app-capable' <<<"$PWA_BODY" || fail "integracao iPhone ausente"
grep -q 'createAnalyser' <<<"$PWA_BODY" || fail "VU real WebAudio ausente"
ok "/listen/ Web App funcional"

printf '\n===== 8. MANIFEST / SERVICE WORKER / ICONES =====\n'
MANIFEST_HEADERS="$(curl -ksSI --resolve "$PUBLIC_DOMAIN:443:127.0.0.1" "$PUBLIC_HOST/listen/manifest.webmanifest" | tr -d '\r')"
MANIFEST_CT="$(awk 'BEGIN{IGNORECASE=1}/^content-type:/{print $2}' <<<"$MANIFEST_HEADERS" | tail -1)"
[[ "$MANIFEST_CT" == application/manifest+json* || "$MANIFEST_CT" == application/json* ]] || fail "manifest content-type invalido: $MANIFEST_CT"
SW_HEADERS="$(curl -ksSI --resolve "$PUBLIC_DOMAIN:443:127.0.0.1" "$PUBLIC_HOST/listen/sw.js" | tr -d '\r')"
SW_CT="$(awk 'BEGIN{IGNORECASE=1}/^content-type:/{print $2}' <<<"$SW_HEADERS" | tail -1)"
[[ "$SW_CT" == application/javascript* || "$SW_CT" == text/javascript* ]] || fail "service worker content-type invalido: $SW_CT"
for n in 192 512; do
  H="$(curl -ksSI --resolve "$PUBLIC_DOMAIN:443:127.0.0.1" "$PUBLIC_HOST/listen/icon-$n.png" | tr -d '\r')"
  grep -qi '^HTTP/2 200\|^HTTP/1\.1 200' <<<"$H" || fail "icone $n HTTP invalido"
  grep -qi '^content-type: image/png' <<<"$H" || fail "icone $n content-type invalido"
done
ok "PWA instalavel: manifest, service worker e icones PNG"

printf '\n===== 9. APK ANDROID =====\n'
APK_HEADERS="$(curl -ksSI --resolve "$PUBLIC_DOMAIN:443:127.0.0.1" "$PUBLIC_HOST/downloads/apps/RadioStudioSat-latest.apk" | tr -d '\r')"
grep -qi '^HTTP/2 200\|^HTTP/1\.1 200' <<<"$APK_HEADERS" || fail "APK latest HTTP invalido"
grep -qi '^content-type: application/vnd.android.package-archive' <<<"$APK_HEADERS" || fail "APK latest content-type invalido"
ok "APK Android"

printf '\n===== 10. STREAMS E CORS =====\n'
for id in radioprincipal radiopop radiorock radioclassicas radiocountry; do
  url="https://$STREAM_DOMAIN/$id/index.m3u8"
  body="$(curl -ksS --max-time 10 "$url" || true)"
  grep -q '#EXTM3U' <<<"$body" || fail "HLS falhou: $id"
  headers="$(curl -ksSI -H "Origin: $PUBLIC_HOST" "$url" | tr -d '\r')"
  grep -qi "^access-control-allow-origin: $PUBLIC_HOST" <<<"$headers" || fail "CORS HLS ausente: $id"
  echo "PASS  $id HLS+CORS"
done

printf '\n===== 11. VALIDACAO PUBLICA =====\n'
PUB_APP="$(curl -ksS --max-time 15 "$PUBLIC_HOST/app/")"
PUB_PWA="$(curl -ksS --max-time 15 "$PUBLIC_HOST/listen/")"
grep -q '<title>Instalar Radio Studio Sat</title>' <<<"$PUB_APP" || fail "publico /app/ incorreto"
grep -q '<title>Radio Studio Sat</title>' <<<"$PUB_PWA" || fail "publico /listen/ incorreto"
ok "rotas publicas"

printf '\n========================================\n'
printf 'STUDIOSAT_UNIVERSAL=PASS\n'
printf 'INSTALLER=%s/app/\n' "$PUBLIC_HOST"
printf 'WEB_APP=%s/listen/\n' "$PUBLIC_HOST"
printf 'ANDROID_APK=%s/downloads/apps/RadioStudioSat-latest.apk\n' "$PUBLIC_HOST"
printf 'WINDOWS=PWA_INSTALLABLE_EDGE_CHROME\n'
printf 'IPHONE=PWA_SAFARI_ADD_TO_HOME_SCREEN\n'
printf 'ANDROID=NATIVE_APK_AND_PWA\n'
printf 'SMART_TV=WEB_APP_BROWSER_REMOTE_READY\n'
printf 'NATIVE_IOS=REQUIRES_APPLE_DEVELOPER_SIGNING_TESTFLIGHT_OR_APP_STORE\n'
printf 'BACKUP=%s\n' "$BACKUP"
printf '========================================\n'
