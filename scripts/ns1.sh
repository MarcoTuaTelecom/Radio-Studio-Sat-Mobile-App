#!/usr/bin/env bash
set -euo pipefail

VERSION="${VERSION:-1.0.0}"
REPO="/root/Radio-Studio-Sat-Mobile-App"
KEY="/root/.ssh/id_ed25519_studiosat_mobile"
DEFAULT_PORTAL_ROOT="/var/www/studiosat-radio-portal"
PORTAL_HOST="www.radio.studiosatweb.com.br"
PORTAL="https://$PORTAL_HOST"
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
for c in git ssh ssh-keygen curl python3 grep sha256sum nginx flock cp mkdir; do command -v "$c" >/dev/null || die "comando ausente: $c"; done
[[ -f "$KEY" ]] || die "chave ausente: $KEY"
[[ -f "$KEY.pub" ]] || die "chave publica ausente: $KEY.pub"
[[ -d "$REPO/.git" ]] || die "repositorio ausente: $REPO"

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

for f in App.tsx app.json package.json eas.json tsconfig.json src/config/stations.ts src/services/api.ts src/components/MediaCarousel.tsx src/components/StationSelector.tsx src/components/VuMeter.tsx scripts/deploy-download-page.sh scripts/ns1.sh web/download/index.html; do
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

NGINX_DUMP="/tmp/studiosat-nginx-$$.txt"
nginx -T >"$NGINX_DUMP" 2>&1
ok "nginx"

mapfile -t PORTAL_ROOTS < <(python3 - "$PORTAL_HOST" "$NGINX_DUMP" <<'PY'
import re,sys
host=sys.argv[1]
lines=open(sys.argv[2],encoding='utf-8',errors='replace').read().splitlines()
roots=[]
i=0
while i < len(lines):
    s=lines[i].split('#',1)[0]
    if re.match(r'^\s*server\s*\{',s):
        block=[lines[i]]
        depth=s.count('{')-s.count('}')
        i+=1
        while i < len(lines) and depth>0:
            t=lines[i].split('#',1)[0]
            block.append(lines[i])
            depth += t.count('{')-t.count('}')
            i+=1
        b='\n'.join(block)
        names=[]
        for m in re.finditer(r'(?m)^\s*server_name\s+([^;]+);',b): names += m.group(1).split()
        listens=[m.group(1) for m in re.finditer(r'(?m)^\s*listen\s+([^;]+);',b)]
        if host in names and any(re.search(r'(^|:)443\b|\b443\b',x) for x in listens):
            m=re.search(r'(?m)^\s*root\s+([^;]+);',b)
            if m:
                r=m.group(1).strip().strip('"\'')
                if r not in roots: roots.append(r)
        continue
    i+=1
for r in roots: print(r)
PY
)

if (( ${#PORTAL_ROOTS[@]} == 0 )); then
  warn "nginx nao revelou root do host; usando $DEFAULT_PORTAL_ROOT"
  PORTAL_ROOTS=("$DEFAULT_PORTAL_ROOT")
fi
PORTAL_ROOT="${PORTAL_ROOTS[0]}"
[[ -d "$PORTAL_ROOT" ]] || die "root ativo do portal nao existe: $PORTAL_ROOT"
[[ -f "$PORTAL_ROOT/index.html" ]] || die "home do root ativo nao existe: $PORTAL_ROOT/index.html"
ok "root nginx primario $PORTAL_ROOT"
for r in "${PORTAL_ROOTS[@]}"; do printf 'INFO  nginx root candidato: %s\n' "$r"; done

HOME_SHA="$(sha256sum "$PORTAL_ROOT/index.html" | awk '{print $1}')"
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
  then ok "CMS content publico 5 emissoras"; else warn "CMS content publico JSON inesperado"; fi
elif [[ -f /var/lib/studiosat-portal/content.json ]] && python3 - <<'PY'
import json
x=json.load(open('/var/lib/studiosat-portal/content.json'))
ids={s.get('id') for s in x.get('stations',[])}
assert ids=={'radioprincipal','radiopop','radiorock','radioclassicas','radiocountry'}, ids
PY
then
  warn "CMS content publico HTTP=$CC; arquivo local possui as 5 emissoras"
else
  warn "CMS content indisponivel HTTP=$CC"
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
[[ -f "$PORTAL_ROOT/app/index.html" ]] || die "pagina /app/index.html nao foi criada"
grep -q '<title>Baixar Radio Studio Sat</title>' "$PORTAL_ROOT/app/index.html" || die "arquivo local /app/index.html invalido"
ok "arquivo local /app/index.html"

# Se houver mais de um vhost/root concorrente para o mesmo host, espelha somente /app.
# Isso nao altera a home nem a configuracao do nginx.
MIRROR_BASE="/var/backups/studiosat/app-root-mirror/$(date -u +%Y%m%dT%H%M%SZ)"
for r in "${PORTAL_ROOTS[@]}"; do
  [[ "$r" == "$PORTAL_ROOT" ]] && continue
  [[ -d "$r" ]] || continue
  mkdir -p "$MIRROR_BASE"
  if [[ -e "$r/app" ]]; then cp -a "$r/app" "$MIRROR_BASE/$(echo "$r" | tr '/' '_').app.previous"; fi
  rm -rf "$r/app"
  cp -a "$PORTAL_ROOT/app" "$r/app"
  ok "espelho /app em $r"
done

STAMP="$(date +%s)"
ORIGIN_FILE=/tmp/studiosat-app-origin.html
origin_test(){
  local code
  code="$(curl -ksS --resolve "$PORTAL_HOST:443:127.0.0.1" --connect-timeout 4 --max-time 15 -o "$ORIGIN_FILE" -w '%{http_code}' "$PORTAL/app/index.html?v=$STAMP" || true)"
  [[ "$code" == 200 ]] && grep -q '<title>Baixar Radio Studio Sat</title>' "$ORIGIN_FILE"
}

if origin_test; then
  ok "origem /app/index.html correta"
else
  warn "origem ainda nao usa o arquivo publicado; diagnosticando vhost"
  printf 'INFO  titulo recebido: '
  grep -o '<title>[^<]*</title>' "$ORIGIN_FILE" 2>/dev/null | head -1 || true
  printf 'INFO  server blocks candidatos:\n'
  python3 - "$PORTAL_HOST" "$NGINX_DUMP" <<'PY'
import re,sys
host=sys.argv[1]; txt=open(sys.argv[2],encoding='utf-8',errors='replace').read()
for b in re.findall(r'(?ms)^\s*server\s*\{.*?^\}',txt):
    if host in b:
        print('---')
        for line in b.splitlines():
            if re.search(r'\b(server_name|listen|root|location)\b',line): print(line.strip())
PY
  die "vhost ativo de $PORTAL_HOST nao esta servindo nenhum root detectado com /app/index.html"
fi

PUBLIC_FILE=/tmp/studiosat-app-public.html
PUBLIC_CODE="$(curl -ksSL --connect-timeout 5 --max-time 20 -o "$PUBLIC_FILE" -w '%{http_code}' "$PORTAL/app/index.html?v=$STAMP" || true)"
[[ "$PUBLIC_CODE" == 200 ]] || die "publico /app/index.html HTTP=$PUBLIC_CODE"
grep -q '<title>Baixar Radio Studio Sat</title>' "$PUBLIC_FILE" || die "publico /app/index.html conteudo invalido"
ok "publico /app/index.html correto"

DIR_CODE="$(curl -ksSL --connect-timeout 5 --max-time 15 -o /tmp/studiosat-app-dir.html -w '%{http_code}' "$PORTAL/app/?v=$STAMP" || true)"
[[ "$DIR_CODE" == 200 ]] && ok "/app/ HTTP 200" || warn "/app/ HTTP=$DIR_CODE"

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
echo "APP_EXACT=$PORTAL/app/index.html"
echo "ROOT=$PORTAL_ROOT"
echo "REPORT=$REPORT"
echo '========================================'
