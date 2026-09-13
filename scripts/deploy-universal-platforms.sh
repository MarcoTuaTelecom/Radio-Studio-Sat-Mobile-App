#!/usr/bin/env bash
set -Eeuo pipefail

REPO="${REPO:-/root/Radio-Studio-Sat-Mobile-App}"
PORTAL_ROOT="${PORTAL_ROOT:-/var/www/studiosat-radio-portal}"
PUBLIC_HOST="${PUBLIC_HOST:-https://www.radio.studiosatweb.com.br}"
PUBLIC_DOMAIN="www.radio.studiosatweb.com.br"
STREAM_DOMAIN="radio.studiosatweb.com.br"
VERSION="${VERSION:-1.1.0}"
PWA_SRC="$REPO/web/pwa"
PWA_DEST="$PORTAL_ROOT/listen"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP="/var/backups/studiosat/model-ui-$TS"

ok(){ printf '\nPASS  %s\n' "$*"; }
fail(){ printf '\nFAIL  %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || fail "execute como root"
for cmd in bash python3 curl nginx git sha256sum find mktemp; do command -v "$cmd" >/dev/null 2>&1 || fail "comando ausente: $cmd"; done
[[ -d "$REPO/.git" ]] || fail "repositorio ausente"
[[ -f "$PWA_SRC/index.html" ]] || fail "PWA ausente"
[[ -f "$PWA_SRC/manifest.webmanifest" ]] || fail "manifest PWA ausente"
[[ -f "$PORTAL_ROOT/index.html" ]] || fail "portal root invalido"

hls_check(){
  local id="$1" url h b c code cors
  url="https://$STREAM_DOMAIN/$id/index.m3u8"
  h="$(mktemp)"; b="$(mktemp)"; c="$(mktemp)"
  code="$(curl -ksS -L --max-redirs 6 -D "$h" -o "$b" -w '%{http_code}' \
    -H "Origin: $PUBLIC_HOST" -c "$c" -b "$c" "$url" || true)"
  cors="$(python3 - "$h" <<'PY'
import re,sys
raw=open(sys.argv[1],encoding='iso-8859-1').read().replace('\r\n','\n')
blocks=[b for b in re.split(r'\n\n+',raw) if b.lstrip().startswith('HTTP/')]
last=blocks[-1] if blocks else ''
m=re.search(r'(?im)^access-control-allow-origin:\s*(.+?)\s*$',last)
print(m.group(1).strip() if m else '')
PY
)"
  printf 'HLS_CHECK id=%s http=%s cors=%s\n' "$id" "$code" "${cors:-MISSING}"
  if [[ "$code" == "200" ]] && grep -q '#EXTM3U' "$b" && { [[ "$cors" == "$PUBLIC_HOST" ]] || [[ "$cors" == "*" ]]; }; then
    rm -f "$h" "$b" "$c"
    return 0
  fi
  rm -f "$h" "$b" "$c"
  return 1
}

printf '\n===== 0. NGINX EXISTENTE =====\n'
nginx -t
ok "nginx atual valido; nenhuma location sera reescrita"

# Seleciona o APK real mais recente sem renomear uma versao antiga como nova.
APK_SOURCE="${APK_SOURCE:-}"
APK_VERSION=""
if [[ -n "$APK_SOURCE" ]]; then
  [[ -f "$APK_SOURCE" ]] || fail "APK_SOURCE ausente: $APK_SOURCE"
else
  exact="/root/builds/RadioStudioSat-v${VERSION}.apk"
  exact_public="$PORTAL_ROOT/downloads/apps/RadioStudioSat-v${VERSION}.apk"
  if [[ -f "$exact" ]]; then
    APK_SOURCE="$exact"; APK_VERSION="$VERSION"
  elif [[ -f "$exact_public" ]]; then
    APK_SOURCE="$exact_public"; APK_VERSION="$VERSION"
  else
    latest_versioned="$(find "$PORTAL_ROOT/downloads/apps" -maxdepth 1 -type f -name 'RadioStudioSat-v*.apk' 2>/dev/null | sort -V | tail -1 || true)"
    [[ -n "$latest_versioned" ]] || fail "nenhum APK versionado existente encontrado"
    APK_SOURCE="$latest_versioned"
  fi
fi

if [[ -z "$APK_VERSION" ]]; then
  base="$(basename "$APK_SOURCE")"
  if [[ "$base" =~ ^RadioStudioSat-v([0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9._-]+)?)\.apk$ ]]; then
    APK_VERSION="${BASH_REMATCH[1]}"
  else
    sha="$(sha256sum "$APK_SOURCE" | awk '{print $1}')"
    same=""
    while IFS= read -r f; do
      [[ "$(sha256sum "$f" | awk '{print $1}')" == "$sha" ]] && { same="$f"; break; }
    done < <(find "$PORTAL_ROOT/downloads/apps" -maxdepth 1 -type f -name 'RadioStudioSat-v*.apk' 2>/dev/null | sort -V -r)
    [[ -n "$same" ]] || fail "nao foi possivel determinar a versao real do APK"
    base="$(basename "$same")"
    APK_VERSION="${base#RadioStudioSat-v}"; APK_VERSION="${APK_VERSION%.apk}"
  fi
fi

mkdir -p "$BACKUP"
[[ -d "$PWA_DEST" ]] && cp -a "$PWA_DEST" "$BACKUP/listen.previous"
[[ -d "$PORTAL_ROOT/app" ]] && cp -a "$PORTAL_ROOT/app" "$BACKUP/app.previous"

echo "UI_VERSION=$VERSION"
echo "APK_SOURCE=$APK_SOURCE"
echo "APK_VERSION=$APK_VERSION"

printf '\n===== 1. CENTRAL /app/ =====\n'
VERSION="$APK_VERSION" APK_SOURCE="$APK_SOURCE" PORTAL_ROOT="$PORTAL_ROOT" PUBLIC_HOST="$PUBLIC_HOST" \
  bash "$REPO/scripts/deploy-download-page.sh"
ok "central de instalacao publicada sem falsificar versao do APK"

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
# O host de streaming faz um 302 de cookieCheck antes do manifesto. Isso e normal.
# Validamos o GET final, seguindo redirect, e aceitamos CORS publico '*' ou origem exata.
if ! hls_check radioprincipal; then
  echo "HLS/CORS ainda nao passou; executando corretor seguro..."
  HOST="$STREAM_DOMAIN" ORIGIN="$PUBLIC_HOST" bash "$REPO/scripts/fix-hls-cors.sh"
  hls_check radioprincipal || fail "HLS radioprincipal continua invalido apos ajuste"
fi
ok "HLS/CORS funcional atraves do redirect cookieCheck"

printf '\n===== 4. NGINX FINAL =====\n'
nginx -t
ok "nginx continua valido"

printf '\n===== 5. VALIDACAO /app/ =====\n'
APP_BODY="$(curl -ksS --resolve "$PUBLIC_DOMAIN:443:127.0.0.1" "$PUBLIC_HOST/app/")"
grep -q '<title>Instalar Radio Studio Sat</title>' <<<"$APP_BODY" || fail "/app/ nao entrega a central correta"
grep -q 'iPhone / iPad' <<<"$APP_BODY" || fail "/app/ sem iPhone"
grep -q 'Windows' <<<"$APP_BODY" || fail "/app/ sem Windows"
grep -q 'Android' <<<"$APP_BODY" || fail "/app/ sem Android"
ok "/app/ central universal"

printf '\n===== 6. VALIDACAO /listen/ MODELO APROVADO =====\n'
PWA_BODY="$(curl -ksS --resolve "$PUBLIC_DOMAIN:443:127.0.0.1" "$PUBLIC_HOST/listen/")"
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
ok "APK Android continua publicado (versao $APK_VERSION)"

printf '\n===== 9. CINCO STREAMS =====\n'
for id in radioprincipal radiopop radiorock radioclassicas radiocountry; do
  hls_check "$id" || fail "HLS/CORS falhou: $id"
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
printf 'UI_VERSION=%s\n' "$VERSION"
printf 'APK_VERSION=%s\n' "$APK_VERSION"
printf 'INSTALLER=%s/app/\n' "$PUBLIC_HOST"
printf 'APP=%s/listen/\n' "$PUBLIC_HOST"
printf 'ANDROID_APK=%s/downloads/apps/RadioStudioSat-latest.apk\n' "$PUBLIC_HOST"
printf 'WINDOWS=PWA\n'
printf 'IPHONE=PWA_SAFARI\n'
printf 'SMART_TV=WEB_APP\n'
printf 'HLS_REDIRECT_COOKIECHECK=SUPPORTED\n'
printf 'NGINX_ROUTES=PRESERVED_NOT_REWRITTEN\n'
printf 'BACKUP=%s\n' "$BACKUP"
printf '========================================\n'
