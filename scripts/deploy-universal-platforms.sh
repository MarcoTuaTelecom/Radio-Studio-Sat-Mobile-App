#!/usr/bin/env bash
set -Eeuo pipefail

REPO="${REPO:-/root/Radio-Studio-Sat-Mobile-App}"
PORTAL_ROOT="${PORTAL_ROOT:-/var/www/studiosat-radio-portal}"
PUBLIC_HOST="${PUBLIC_HOST:-https://www.radio.studiosatweb.com.br}"
PUBLIC_DOMAIN="www.radio.studiosatweb.com.br"
STREAM_DOMAIN="radio.studiosatweb.com.br"
VERSION="${VERSION:-1.0.0}"
PWA_SRC="$REPO/web/pwa"
PWA_DEST="$PORTAL_ROOT/listen"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP="/var/backups/studiosat/model-ui-$TS"

ok(){ printf '\nPASS  %s\n' "$*"; }
fail(){ printf '\nFAIL  %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || fail "execute como root"
for cmd in bash python3 curl nginx git; do command -v "$cmd" >/dev/null 2>&1 || fail "comando ausente: $cmd"; done
[[ -d "$REPO/.git" ]] || fail "repositorio ausente"
[[ -f "$PWA_SRC/index.html" ]] || fail "PWA ausente"
[[ -f "$PWA_SRC/manifest.webmanifest" ]] || fail "manifest PWA ausente"
[[ -f "$PORTAL_ROOT/index.html" ]] || fail "portal root invalido"

# O roteamento /app/ e /listen/ já foi corrigido no NGINX e está funcionando.
# Este script NÃO reescreve locations do NGINX. Ele apenas valida antes/depois.
printf '\n===== 0. NGINX EXISTENTE =====\n'
nginx -t
ok "nginx atual valido; nenhuma rota sera reescrita"

APK_SOURCE="${APK_SOURCE:-}"
if [[ -z "$APK_SOURCE" ]]; then
  for candidate in \
    "/root/builds/RadioStudioSat-v${VERSION}.apk" \
    "$PORTAL_ROOT/downloads/apps/RadioStudioSat-v${VERSION}.apk" \
    "$PORTAL_ROOT/downloads/apps/RadioStudioSat-latest.apk"; do
    if [[ -f "$candidate" ]]; then APK_SOURCE="$candidate"; break; fi
  done
fi
[[ -n "$APK_SOURCE" && -f "$APK_SOURCE" ]] || fail "nenhum APK existente encontrado"

mkdir -p "$BACKUP"
[[ -d "$PWA_DEST" ]] && cp -a "$PWA_DEST" "$BACKUP/listen.previous"
[[ -d "$PORTAL_ROOT/app" ]] && cp -a "$PORTAL_ROOT/app" "$BACKUP/app.previous"

echo "APK_SOURCE=$APK_SOURCE"

printf '\n===== 1. CENTRAL /app/ =====\n'
VERSION="$VERSION" APK_SOURCE="$APK_SOURCE" PORTAL_ROOT="$PORTAL_ROOT" PUBLIC_HOST="$PUBLIC_HOST" \
  bash "$REPO/scripts/deploy-download-page.sh"
ok "central de instalacao publicada"

printf '\n===== 2. APP UNIVERSAL /listen/ =====\n'
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
ok "interface do modelo e PWA publicadas"

printf '\n===== 3. HLS / CORS =====\n'
HLS_URL="https://$STREAM_DOMAIN/radioprincipal/index.m3u8"
HLS_HEADERS="$(curl -ksSI -H "Origin: $PUBLIC_HOST" "$HLS_URL" | tr -d '\r')"
if ! grep -qi "^access-control-allow-origin: $PUBLIC_HOST" <<<"$HLS_HEADERS"; then
  echo "CORS ainda ausente; aplicando somente a correcao segura do host HLS..."
  [[ -f "$REPO/scripts/fix-hls-cors.sh" ]] || fail "fix-hls-cors.sh ausente"
  HOST="$STREAM_DOMAIN" ORIGIN="$PUBLIC_HOST" bash "$REPO/scripts/fix-hls-cors.sh"
fi
ok "CORS HLS pronto"

printf '\n===== 4. NGINX FINAL =====\n'
nginx -t
ok "nginx continua valido"

printf '\n===== 5. VALIDACAO /app/ =====\n'
APP_HEADERS="$(curl -ksSI --resolve "$PUBLIC_DOMAIN:443:127.0.0.1" "$PUBLIC_HOST/app/" | tr -d '\r')"
APP_BODY="$(curl -ksS --resolve "$PUBLIC_DOMAIN:443:127.0.0.1" "$PUBLIC_HOST/app/")"
printf '%s\n' "$APP_HEADERS" | head -20
grep -q '<title>Instalar Radio Studio Sat</title>' <<<"$APP_BODY" || fail "/app/ nao entrega a central correta"
grep -q 'iPhone / iPad' <<<"$APP_BODY" || fail "/app/ sem iPhone"
grep -q 'Windows' <<<"$APP_BODY" || fail "/app/ sem Windows"
grep -q 'Android' <<<"$APP_BODY" || fail "/app/ sem Android"
ok "/app/ central universal"

printf '\n===== 6. VALIDACAO /listen/ MODELO APROVADO =====\n'
PWA_HEADERS="$(curl -ksSI --resolve "$PUBLIC_DOMAIN:443:127.0.0.1" "$PUBLIC_HOST/listen/" | tr -d '\r')"
PWA_BODY="$(curl -ksS --resolve "$PUBLIC_DOMAIN:443:127.0.0.1" "$PUBLIC_HOST/listen/")"
printf '%s\n' "$PWA_HEADERS" | head -20
for marker in \
  '<title>Radio Studio Sat</title>' \
  'A MÚSICA NOS CONECTA' \
  'TRADUÇÃO' \
  'Nossas Emissoras' \
  'Conteúdo, notícia e publicidade' \
  'beforeinstallprompt' \
  'createAnalyser' \
  'mediaSession'; do
  grep -q "$marker" <<<"$PWA_BODY" || fail "/listen/ sem marcador: $marker"
done
ok "/listen/ corresponde ao novo app e tem player/VU/PWA/MediaSession"

printf '\n===== 7. PWA =====\n'
MANIFEST_HEADERS="$(curl -ksSI --resolve "$PUBLIC_DOMAIN:443:127.0.0.1" "$PUBLIC_HOST/listen/manifest.webmanifest" | tr -d '\r')"
MANIFEST_CT="$(awk 'BEGIN{IGNORECASE=1}/^content-type:/{print $2}' <<<"$MANIFEST_HEADERS" | tail -1)"
[[ "$MANIFEST_CT" == application/manifest+json* || "$MANIFEST_CT" == application/json* ]] || fail "manifest content-type invalido: $MANIFEST_CT"
SW_HEADERS="$(curl -ksSI --resolve "$PUBLIC_DOMAIN:443:127.0.0.1" "$PUBLIC_HOST/listen/sw.js" | tr -d '\r')"
SW_CT="$(awk 'BEGIN{IGNORECASE=1}/^content-type:/{print $2}' <<<"$SW_HEADERS" | tail -1)"
[[ "$SW_CT" == application/javascript* || "$SW_CT" == text/javascript* ]] || fail "service worker content-type invalido: $SW_CT"
for n in 192 512; do
  H="$(curl -ksSI --resolve "$PUBLIC_DOMAIN:443:127.0.0.1" "$PUBLIC_HOST/listen/icon-$n.png" | tr -d '\r')"
  grep -qiE '^HTTP/(2|1\.1) 200' <<<"$H" || fail "icone $n HTTP invalido"
  grep -qi '^content-type: image/png' <<<"$H" || fail "icone $n invalido"
done
ok "PWA instalavel"

printf '\n===== 8. APK EXISTENTE =====\n'
APK_HEADERS="$(curl -ksSI --resolve "$PUBLIC_DOMAIN:443:127.0.0.1" "$PUBLIC_HOST/downloads/apps/RadioStudioSat-latest.apk" | tr -d '\r')"
grep -qiE '^HTTP/(2|1\.1) 200' <<<"$APK_HEADERS" || fail "APK latest HTTP invalido"
grep -qi '^content-type: application/vnd.android.package-archive' <<<"$APK_HEADERS" || fail "APK latest content-type invalido"
ok "APK Android continua publicado"

printf '\n===== 9. CINCO STREAMS =====\n'
for id in radioprincipal radiopop radiorock radioclassicas radiocountry; do
  url="https://$STREAM_DOMAIN/$id/index.m3u8"
  body="$(curl -ksS --max-time 10 "$url" || true)"
  grep -q '#EXTM3U' <<<"$body" || fail "HLS falhou: $id"
  headers="$(curl -ksSI -H "Origin: $PUBLIC_HOST" "$url" | tr -d '\r')"
  grep -qi "^access-control-allow-origin: $PUBLIC_HOST" <<<"$headers" || fail "CORS HLS ausente: $id"
  echo "PASS  $id"
done

printf '\n===== 10. PUBLICO =====\n'
PUB_APP="$(curl -ksS --max-time 15 "$PUBLIC_HOST/app/")"
PUB_PWA="$(curl -ksS --max-time 15 "$PUBLIC_HOST/listen/")"
grep -q '<title>Instalar Radio Studio Sat</title>' <<<"$PUB_APP" || fail "publico /app/ incorreto"
grep -q 'A MÚSICA NOS CONECTA' <<<"$PUB_PWA" || fail "publico /listen/ ainda nao recebeu o novo modelo"
ok "publicacao externa"

printf '\n========================================\n'
printf 'STUDIOSAT_MODEL_UI=PASS\n'
printf 'INSTALLER=%s/app/\n' "$PUBLIC_HOST"
printf 'APP=%s/listen/\n' "$PUBLIC_HOST"
printf 'ANDROID_APK=%s/downloads/apps/RadioStudioSat-latest.apk\n' "$PUBLIC_HOST"
printf 'WINDOWS=PWA\n'
printf 'IPHONE=PWA_SAFARI\n'
printf 'SMART_TV=WEB_APP\n'
printf 'NGINX_ROUTES=PRESERVED_NOT_REWRITTEN\n'
printf 'BACKUP=%s\n' "$BACKUP"
printf '========================================\n'
