#!/usr/bin/env bash
set -euo pipefail

VERSION="${VERSION:-1.0.0}"
REPO="/root/Radio-Studio-Sat-Mobile-App"
KEY="/root/.ssh/id_ed25519_studiosat_mobile"
PORTAL_ROOT="/var/www/studiosat-radio-portal"
PORTAL="https://www.radio.studiosatweb.com.br"
PLAYER="https://radio.studiosatweb.com.br"
REPORT="/tmp/STUDIOSAT-MOBILE-NS1-$(date -u +%Y%m%dT%H%M%SZ).log"
APK_SOURCE="${APK_SOURCE:-}"
PLAY_STORE_URL="${PLAY_STORE_URL:-}"
APP_STORE_URL="${APP_STORE_URL:-}"

exec > >(tee "$REPORT") 2>&1
ok(){ printf 'PASS  %s\n' "$*"; }
warn(){ printf 'WARN  %s\n' "$*"; }
die(){ printf 'FAIL  %s\nREPORT=%s\n' "$*" "$REPORT" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "execute como root"
for c in git ssh ssh-keygen curl python3 grep sha256sum nginx flock; do command -v "$c" >/dev/null || die "comando ausente: $c"; done
[[ -f "$KEY" ]] || die "chave ausente: $KEY"
[[ -f "$KEY.pub" ]] || die "chave publica ausente: $KEY.pub"
[[ -d "$REPO/.git" ]] || die "repositorio ausente: $REPO"
[[ -f "$PORTAL_ROOT/index.html" ]] || die "portal ausente: $PORTAL_ROOT/index.html"

exec 9>/var/lock/studiosat-mobile-ns1.lock
flock -n 9 || die "outra execucao esta ativa"
ok "host $(hostname -f 2>/dev/null || hostname)"
ok "ssh key $(ssh-keygen -lf "$KEY.pub" | awk '{print $2}')"

SSH=(ssh -i "$KEY" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new)
SSH_OUT=""
SSH_RC=0
if SSH_OUT="$("${SSH[@]}" -T git@github.com 2>&1)"; then SSH_RC=0; else SSH_RC=$?; fi
printf '%s\n' "$SSH_OUT"
grep -qi 'successfully authenticated' <<<"$SSH_OUT" || die "GitHub SSH nao autenticou (rc=$SSH_RC)"
ok "GitHub SSH"

cd "$REPO"
git config core.sshCommand "ssh -i $KEY -o IdentitiesOnly=yes"
[[ -z "$(git status --porcelain)" ]] || die "working tree tem alteracoes locais"
git fetch origin main
git checkout -q main
git pull --ff-only origin main
ok "git $(git rev-parse --short HEAD)"

for f in App.tsx app.json package.json eas.json tsconfig.json src/config/stations.ts src/services/api.ts src/components/MediaCarousel.tsx src/components/StationSelector.tsx src/components/VuMeter.tsx scripts/deploy-download-page.sh web/download/index.html; do
  [[ -f "$f" ]] || die "arquivo ausente: $f"
done
bash -n scripts/deploy-download-page.sh
bash -n scripts/ns1.sh
python3 - <<'PY'
import json
for f in ('app.json','package.json','eas.json'):
    json.load(open(f,encoding='utf-8'))
a=json.load(open('app.json',encoding='utf-8'))['expo']
assert a['android']['package']=='br.com.studiosatweb.radio'
assert a['ios']['bundleIdentifier']=='br.com.studiosatweb.radio'
PY
ok "fontes/configuracao"

HOME_SHA="$(sha256sum "$PORTAL_ROOT/index.html" | awk '{print $1}')"
nginx -t
ok "nginx"

CODE="$(curl -ksSL --connect-timeout 5 --max-time 15 -o /tmp/studiosat-portal.html -w '%{http_code}' "$PORTAL/")"
[[ "$CODE" == 200 ]] || die "portal HTTP=$CODE"
ok "portal HTTP 200"

for s in radioprincipal radiopop radiorock radioclassicas radiocountry; do
  F="/tmp/$s.m3u8"
  C="$(curl -ksSL --connect-timeout 4 --max-time 15 -o "$F" -w '%{http_code}' "$PLAYER/$s/index.m3u8" || true)"
  [[ "$C" == 200 ]] && grep -q '^#EXTM3U' "$F" || die "$s HLS falhou HTTP=$C"
  ok "$s HLS"
done

HC="$(curl -ksSL --connect-timeout 4 --max-time 12 -o /tmp/studiosat-health.json -w '%{http_code}' "$PORTAL/api/health" || true)"
[[ "$HC" == 200 ]] || die "CMS health HTTP=$HC"
python3 - <<'PY'
import json
assert json.load(open('/tmp/studiosat-health.json')).get('ok') is True
PY
ok "CMS health"

CC="$(curl -ksSL --connect-timeout 4 --max-time 15 -o /tmp/studiosat-content.json -w '%{http_code}' "$PORTAL/api/content" || true)"
if [[ "$CC" == 200 ]]; then
  if python3 - <<'PY'
import json
x=json.load(open('/tmp/studiosat-content.json'))
ids={s.get('id') for s in x.get('stations',[])}
assert ids=={'radioprincipal','radiopop','radiorock','radioclassicas','radiocountry'}, ids
PY
  then
    ok "CMS content 5 emissoras"
  else
    warn "CMS content respondeu 200 mas JSON nao corresponde as 5 emissoras"
  fi
elif [[ -f /var/lib/studiosat-portal/content.json ]] && python3 - <<'PY'
import json
x=json.load(open('/var/lib/studiosat-portal/content.json'))
ids={s.get('id') for s in x.get('stations',[])}
assert ids=={'radioprincipal','radiopop','radiorock','radioclassicas','radiocountry'}, ids
PY
then
  warn "CMS content publico HTTP=$CC; arquivo local possui as 5 emissoras"
else
  warn "CMS content publico HTTP=$CC; nao bloqueia a pagina de download"
fi

for s in radioprincipal radiopop radiorock radioclassicas radiocountry; do
  C="$(curl -ksSL --connect-timeout 3 --max-time 8 -o "/tmp/now-$s.json" -w '%{http_code}' "$PLAYER/assets/now/$s.json" || true)"
  if [[ "$C" == 200 ]] && python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "/tmp/now-$s.json" 2>/dev/null; then ok "now-playing $s"; else warn "now-playing $s indisponivel HTTP=$C"; fi
done

ENVV=("VERSION=$VERSION" "PORTAL_ROOT=$PORTAL_ROOT" "PUBLIC_HOST=$PORTAL")
[[ -n "$APK_SOURCE" ]] && ENVV+=("APK_SOURCE=$APK_SOURCE")
[[ -n "$PLAY_STORE_URL" ]] && ENVV+=("PLAY_STORE_URL=$PLAY_STORE_URL")
[[ -n "$APP_STORE_URL" ]] && ENVV+=("APP_STORE_URL=$APP_STORE_URL")
env "${ENVV[@]}" bash scripts/deploy-download-page.sh

[[ "$(sha256sum "$PORTAL_ROOT/index.html" | awk '{print $1}')" == "$HOME_SHA" ]] || die "home original foi alterada"
[[ -f "$PORTAL_ROOT/app/index.html" ]] || die "pagina /app/ nao foi criada"
AC="$(curl -ksSL --connect-timeout 5 --max-time 15 -o /tmp/studiosat-app.html -w '%{http_code}' "$PORTAL/app/?v=$(date +%s)" || true)"
[[ "$AC" == 200 ]] || die "/app/ HTTP=$AC"
grep -q 'Baixar Radio Studio Sat' /tmp/studiosat-app.html || die "conteudo /app/ invalido"
nginx -t
ok "pagina /app/ publicada"

for s in radioprincipal radiopop radiorock radioclassicas radiocountry; do
  C="$(curl -ksSL --connect-timeout 3 --max-time 10 -o "/tmp/final-$s.m3u8" -w '%{http_code}' "$PLAYER/$s/index.m3u8" || true)"
  [[ "$C" == 200 ]] && grep -q '^#EXTM3U' "/tmp/final-$s.m3u8" || die "pos-deploy $s falhou"
done

echo
echo '========================================'
echo 'STUDIOSAT_MOBILE_NS1=PASS'
echo "APP=$PORTAL/app/"
echo "REPORT=$REPORT"
echo '========================================'
