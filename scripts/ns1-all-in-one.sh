#!/usr/bin/env bash
# Radio Studio Sat — NS1 all-in-one validator/deployer
# Faz preflight do host, autenticação GitHub, sincronização do repositório,
# validação do fonte, health das 5 rádios/CMS, deploy seguro de /app/ e pós-validação.
# NÃO altera a home do portal, NÃO altera NGINX e NÃO instala pacotes do SO.
set -Eeuo pipefail
IFS=$'\n\t'

# Executa a partir de uma cópia temporária para permitir git pull/reexec sem alterar
# o arquivo que o bash está lendo durante a própria execução.
if [[ "${STUDIOSAT_SELF_COPY:-0}" != "1" ]]; then
  SELF_TMP="/tmp/studiosat-mobile-ns1.$$.$RANDOM.sh"
  cp -- "$0" "$SELF_TMP"
  chmod 0700 "$SELF_TMP"
  exec env STUDIOSAT_SELF_COPY=1 STUDIOSAT_ORIGINAL_SCRIPT="$0" bash "$SELF_TMP" "$@"
fi

VERSION="${VERSION:-1.0.0}"
REPO_DIR="${REPO_DIR:-/root/Radio-Studio-Sat-Mobile-App}"
REPO_REMOTE="${REPO_REMOTE:-git@github.com:MarcoTuaTelecom/Radio-Studio-Sat-Mobile-App.git}"
SSH_KEY="${SSH_KEY:-/root/.ssh/id_ed25519_studiosat_mobile}"
PORTAL_ROOT="${PORTAL_ROOT:-/var/www/studiosat-radio-portal}"
PORTAL_HOST="${PORTAL_HOST:-www.radio.studiosatweb.com.br}"
PLAYER_HOST="${PLAYER_HOST:-radio.studiosatweb.com.br}"
PUBLIC_PORTAL="https://${PORTAL_HOST}"
PUBLIC_PLAYER="https://${PLAYER_HOST}"
APK_SOURCE="${APK_SOURCE:-}"
PLAY_STORE_URL="${PLAY_STORE_URL:-}"
APP_STORE_URL="${APP_STORE_URL:-}"
RUN_NODE_VALIDATION="${RUN_NODE_VALIDATION:-auto}"   # auto|1|0
STRICT_NODE="${STRICT_NODE:-0}"                     # 1 = falha se npm/expo/typecheck falhar
REQUIRE_ALL_RADIOS="${REQUIRE_ALL_RADIOS:-1}"      # 1 = as 5 HLS devem passar
REQUIRE_CMS="${REQUIRE_CMS:-1}"                    # 1 = /api/health e /api/content devem passar
NOW_PLAYING_STRICT="${NOW_PLAYING_STRICT:-0}"       # 1 = JSON now-playing obrigatório nas 5
REEXEC_AFTER_PULL="${REEXEC_AFTER_PULL:-1}"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
REPORT_BASE="${REPORT_BASE:-/var/log/studiosat-mobile}"
REPORT_DIR="$REPORT_BASE/ns1-$TS"
REPORT="$REPORT_DIR/REPORT.txt"
SUMMARY="$REPORT_DIR/summary.tsv"
LOCK_FILE="${LOCK_FILE:-/var/lock/studiosat-mobile-ns1.lock}"

mkdir -p "$REPORT_DIR" "$(dirname "$LOCK_FILE")"
touch "$REPORT" "$SUMMARY"
exec > >(tee -a "$REPORT") 2>&1

PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0
RESULTS=()

phase(){ printf '\n===== %s =====\n' "$*"; }
pass(){ PASS_COUNT=$((PASS_COUNT+1)); RESULTS+=("$1\tPASS\t${2:-}"); printf 'PASS  %-30s %s\n' "$1" "${2:-}"; }
warn(){ WARN_COUNT=$((WARN_COUNT+1)); RESULTS+=("$1\tWARN\t${2:-}"); printf 'WARN  %-30s %s\n' "$1" "${2:-}"; }
fail(){ FAIL_COUNT=$((FAIL_COUNT+1)); RESULTS+=("$1\tFAIL\t${2:-}"); printf 'FAIL  %-30s %s\n' "$1" "${2:-}" >&2; }
fatal(){ fail "$1" "${2:-}"; finalize 1; }
need(){ command -v "$1" >/dev/null 2>&1 || fatal "tool:$1" "comando ausente"; }

finalize(){
  local rc="${1:-0}"
  printf 'check\tstatus\tdetail\n' > "$SUMMARY"
  local row
  for row in "${RESULTS[@]:-}"; do printf '%b\n' "$row" >> "$SUMMARY"; done
  printf '\n===== RESUMO =====\n'
  printf 'PASS=%d WARN=%d FAIL=%d\n' "$PASS_COUNT" "$WARN_COUNT" "$FAIL_COUNT"
  printf 'HEAD=%s\n' "$(git -C "$REPO_DIR" rev-parse HEAD 2>/dev/null || echo unavailable)"
  printf 'REPORT=%s\nSUMMARY=%s\n' "$REPORT" "$SUMMARY"
  if (( FAIL_COUNT > 0 || rc != 0 )); then
    echo 'NS1_MOBILE_RESULT=FAIL'
    exit 1
  fi
  if (( WARN_COUNT > 0 )); then
    echo 'NS1_MOBILE_RESULT=PASS_WITH_WARNINGS'
  else
    echo 'NS1_MOBILE_RESULT=PASS'
  fi
  exit 0
}

on_err(){
  local rc=$? line=${BASH_LINENO[0]:-?} cmd=${BASH_COMMAND:-?}
  fail "unhandled_error" "rc=$rc line=$line cmd=$cmd"
  finalize "$rc"
}
trap on_err ERR
trap 'rm -f "/tmp/studiosat-mobile-ns1.$$"* 2>/dev/null || true' EXIT

phase "A. HOST / CONCORRÊNCIA / FERRAMENTAS"
[[ ${EUID:-$(id -u)} -eq 0 ]] || fatal "root" "execute como root"
pass "root" "uid=0"

for c in bash git ssh curl python3 grep sed awk sha256sum install cp mkdir date find flock; do need "$c"; done
pass "base_tools" "ok"

exec 9>"$LOCK_FILE"
flock -n 9 || fatal "lock" "já existe outra execução: $LOCK_FILE"
pass "lock" "$LOCK_FILE"

HOSTNAME_NOW="$(hostname -f 2>/dev/null || hostname)"
printf 'UTC=%s\nHOST=%s\nVERSION=%s\nREPO_DIR=%s\n' "$TS" "$HOSTNAME_NOW" "$VERSION" "$REPO_DIR"
if [[ "$HOSTNAME_NOW" == ns1* ]]; then pass "host_identity" "$HOSTNAME_NOW"; else warn "host_identity" "esperado ns1*, obtido $HOSTNAME_NOW"; fi

df -h / "$PORTAL_ROOT" 2>/dev/null || true
free -h 2>/dev/null || true
uptime || true

phase "B. CHAVE SSH / GITHUB"
[[ -f "$SSH_KEY" ]] || fatal "ssh_private_key" "não existe: $SSH_KEY"
[[ -f "$SSH_KEY.pub" ]] || fatal "ssh_public_key" "não existe: $SSH_KEY.pub"
chmod 0600 "$SSH_KEY"
chmod 0644 "$SSH_KEY.pub"
SSH_FP="$(ssh-keygen -lf "$SSH_KEY.pub" | awk '{print $2}')"
pass "ssh_key" "$SSH_FP"

SSH_CMD="ssh -i $SSH_KEY -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new"
set +e
SSH_TEST_OUT="$($SSH_CMD -T git@github.com 2>&1)"
SSH_TEST_RC=$?
set -e
printf '%s\n' "$SSH_TEST_OUT"
if grep -qi 'successfully authenticated' <<<"$SSH_TEST_OUT"; then
  pass "github_ssh" "deploy key autenticada"
else
  fatal "github_ssh" "rc=$SSH_TEST_RC autenticação não confirmada"
fi

phase "C. REPOSITÓRIO / SINCRONIZAÇÃO"
if [[ ! -d "$REPO_DIR/.git" ]]; then
  mkdir -p "$(dirname "$REPO_DIR")"
  GIT_SSH_COMMAND="$SSH_CMD" git clone "$REPO_REMOTE" "$REPO_DIR"
  pass "repo_clone" "$REPO_DIR"
else
  pass "repo_exists" "$REPO_DIR"
fi

ACTUAL_REMOTE="$(git -C "$REPO_DIR" remote get-url origin 2>/dev/null || true)"
[[ -n "$ACTUAL_REMOTE" ]] || fatal "git_origin" "origin ausente"
if [[ "$ACTUAL_REMOTE" != "$REPO_REMOTE" ]]; then
  warn "git_origin" "atual=$ACTUAL_REMOTE esperado=$REPO_REMOTE"
else
  pass "git_origin" "$ACTUAL_REMOTE"
fi

git -C "$REPO_DIR" config core.sshCommand "$SSH_CMD"
if [[ -n "$(git -C "$REPO_DIR" status --porcelain)" ]]; then
  git -C "$REPO_DIR" status --short
  fatal "git_worktree" "working tree não está limpa; não vou sobrescrever alterações locais"
fi
pass "git_worktree" "clean"

OLD_HEAD="$(git -C "$REPO_DIR" rev-parse HEAD)"
git -C "$REPO_DIR" fetch origin main
git -C "$REPO_DIR" checkout -q main
git -C "$REPO_DIR" pull --ff-only origin main
NEW_HEAD="$(git -C "$REPO_DIR" rev-parse HEAD)"
pass "git_sync" "$NEW_HEAD"

if [[ "$OLD_HEAD" != "$NEW_HEAD" && "$REEXEC_AFTER_PULL" == "1" && "${STUDIOSAT_REEXECED:-0}" != "1" && -f "$REPO_DIR/scripts/ns1-all-in-one.sh" ]]; then
  echo "INFO script/repo atualizado $OLD_HEAD -> $NEW_HEAD; reiniciando com a versão nova."
  exec env STUDIOSAT_REEXECED=1 \
    VERSION="$VERSION" REPO_DIR="$REPO_DIR" SSH_KEY="$SSH_KEY" PORTAL_ROOT="$PORTAL_ROOT" \
    PORTAL_HOST="$PORTAL_HOST" PLAYER_HOST="$PLAYER_HOST" APK_SOURCE="$APK_SOURCE" \
    PLAY_STORE_URL="$PLAY_STORE_URL" APP_STORE_URL="$APP_STORE_URL" RUN_NODE_VALIDATION="$RUN_NODE_VALIDATION" \
    STRICT_NODE="$STRICT_NODE" REQUIRE_ALL_RADIOS="$REQUIRE_ALL_RADIOS" REQUIRE_CMS="$REQUIRE_CMS" \
    NOW_PLAYING_STRICT="$NOW_PLAYING_STRICT" \
    bash "$REPO_DIR/scripts/ns1-all-in-one.sh"
fi

phase "D. INTEGRIDADE DO PROJETO"
EXPECTED=(
  App.tsx app.json package.json eas.json tsconfig.json
  src/config/stations.ts src/services/api.ts src/types/index.ts
  src/components/MediaCarousel.tsx src/components/StationSelector.tsx src/components/VuMeter.tsx
  scripts/build-release.sh scripts/deploy-download-page.sh scripts/ns1-all-in-one.sh
  web/download/index.html docs/API_CONTRACT.md docs/PUBLISHING.md docs/DOWNLOAD_PAGE_DEPLOY.md
  assets/icon.png assets/adaptive-icon.png assets/splash.png
)
for f in "${EXPECTED[@]}"; do [[ -f "$REPO_DIR/$f" ]] || fatal "source_file" "ausente: $f"; done
pass "source_files" "${#EXPECTED[@]} arquivos críticos presentes"

bash -n "$REPO_DIR/scripts/build-release.sh"
bash -n "$REPO_DIR/scripts/deploy-download-page.sh"
bash -n "$REPO_DIR/scripts/ns1-all-in-one.sh"
pass "shell_syntax" "3 scripts"

python3 - "$REPO_DIR" <<'PY'
import json,sys,pathlib
root=pathlib.Path(sys.argv[1])
for name in ('app.json','package.json','eas.json'):
    json.loads((root/name).read_text(encoding='utf-8'))
app=json.loads((root/'app.json').read_text(encoding='utf-8'))['expo']
assert app['android']['package']=='br.com.studiosatweb.radio', app['android']['package']
assert app['ios']['bundleIdentifier']=='br.com.studiosatweb.radio', app['ios']['bundleIdentifier']
pkg=json.loads((root/'package.json').read_text(encoding='utf-8'))
assert 'expo' in pkg.get('dependencies',{})
print('JSON_CONFIG=PASS package=br.com.studiosatweb.radio')
PY
pass "json_config" "package/bundle corretos"

for s in radioprincipal radiopop radiorock radioclassicas radiocountry; do
  grep -q "$s" "$REPO_DIR/src/config/stations.ts" || fatal "station_config" "ausente: $s"
done
pass "station_config" "5 emissoras"

if grep -Rqs 'REPLACE_WITH_EAS_PROJECT_ID\|YOUR_EAS_PROJECT_ID' "$REPO_DIR/app.json" "$REPO_DIR/.env.example" 2>/dev/null; then
  warn "eas_project_id" "placeholder ainda existe; necessário antes do build de loja"
else
  pass "eas_project_id" "configurado"
fi

phase "E. NODE / TYPESCRIPT / EXPO"
DO_NODE=0
case "$RUN_NODE_VALIDATION" in
  1|yes|true) DO_NODE=1 ;;
  0|no|false) DO_NODE=0 ;;
  auto) if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then DO_NODE=1; fi ;;
  *) fatal "RUN_NODE_VALIDATION" "valor inválido: $RUN_NODE_VALIDATION" ;;
esac

if (( DO_NODE == 1 )); then
  echo "node=$(node --version) npm=$(npm --version)"
  set +e
  (cd "$REPO_DIR" && npm install --no-audit --no-fund)
  NPM_RC=$?
  if (( NPM_RC == 0 )); then
    pass "npm_install" "ok"
    (cd "$REPO_DIR" && npm run typecheck)
    TS_RC=$?
    if (( TS_RC == 0 )); then pass "typecheck" "ok"; else
      if [[ "$STRICT_NODE" == "1" ]]; then set -e; fatal "typecheck" "rc=$TS_RC"; else warn "typecheck" "rc=$TS_RC"; fi
    fi
    (cd "$REPO_DIR" && npx --yes expo-doctor)
    EXPO_RC=$?
    if (( EXPO_RC == 0 )); then pass "expo_doctor" "ok"; else
      if [[ "$STRICT_NODE" == "1" ]]; then set -e; fatal "expo_doctor" "rc=$EXPO_RC"; else warn "expo_doctor" "rc=$EXPO_RC"; fi
    fi
  else
    if [[ "$STRICT_NODE" == "1" ]]; then set -e; fatal "npm_install" "rc=$NPM_RC"; else warn "npm_install" "rc=$NPM_RC; validação Node incompleta"; fi
  fi
  set -e
else
  warn "node_validation" "node/npm ausentes ou RUN_NODE_VALIDATION=0; não instalo toolchain no NS1 automaticamente"
fi

phase "F. NGINX / PORTAL / TLS"
[[ -d "$PORTAL_ROOT" ]] || fatal "portal_root" "não existe: $PORTAL_ROOT"
[[ -f "$PORTAL_ROOT/index.html" ]] || fatal "portal_home" "não existe: $PORTAL_ROOT/index.html"
HOME_SHA_BEFORE="$(sha256sum "$PORTAL_ROOT/index.html" | awk '{print $1}')"
pass "portal_root" "$PORTAL_ROOT"

if command -v nginx >/dev/null 2>&1; then
  nginx -t
  pass "nginx_config" "nginx -t"
  if command -v systemctl >/dev/null 2>&1; then
    if systemctl is-active --quiet nginx; then pass "nginx_service" "active"; else fatal "nginx_service" "not active"; fi
  fi
else
  fatal "nginx" "comando nginx não encontrado"
fi

if command -v openssl >/dev/null 2>&1 && command -v timeout >/dev/null 2>&1; then
  set +e
  CERT_INFO="$(timeout 12 openssl s_client -connect "$PORTAL_HOST:443" -servername "$PORTAL_HOST" </dev/null 2>/dev/null | openssl x509 -noout -subject -issuer -dates 2>/dev/null)"
  CERT_RC=$?
  set -e
  if (( CERT_RC == 0 )) && [[ -n "$CERT_INFO" ]]; then
    printf '%s\n' "$CERT_INFO"
    pass "tls_certificate" "$PORTAL_HOST"
  else
    warn "tls_certificate" "não foi possível inspecionar certificado"
  fi
else
  warn "tls_certificate" "openssl/timeout indisponível"
fi

PUBLIC_HOME_CODE="$(curl -ksSL --connect-timeout 5 --max-time 15 -o "$REPORT_DIR/portal-home.html" -w '%{http_code}' "$PUBLIC_PORTAL/" || true)"
[[ "$PUBLIC_HOME_CODE" == "200" ]] || fatal "portal_public" "HTTP=$PUBLIC_HOME_CODE"
pass "portal_public" "HTTP=200"

LOCAL_HOME_CODE="$(curl -ksS --resolve "$PORTAL_HOST:443:127.0.0.1" --connect-timeout 3 --max-time 10 -o "$REPORT_DIR/portal-home-local.html" -w '%{http_code}' "$PUBLIC_PORTAL/" || true)"
[[ "$LOCAL_HOME_CODE" == "200" ]] || fatal "portal_origin" "HTTP=$LOCAL_HOME_CODE"
pass "portal_origin" "HTTP=200 via 127.0.0.1"

phase "G. CINCO RÁDIOS — HLS PÚBLICO"
RADIO_FAIL=0
for s in radioprincipal radiopop radiorock radioclassicas radiocountry; do
  OUT="$REPORT_DIR/$s.m3u8"
  CODE="$(curl -ksSL --connect-timeout 4 --max-time 15 -o "$OUT" -w '%{http_code}' "$PUBLIC_PLAYER/$s/index.m3u8" || true)"
  if [[ "$CODE" == "200" ]] && grep -q '^#EXTM3U' "$OUT"; then
    pass "hls:$s" "HTTP=200 manifest"
  else
    fail "hls:$s" "HTTP=$CODE ou manifesto inválido"
    RADIO_FAIL=$((RADIO_FAIL+1))
  fi
done
if (( RADIO_FAIL > 0 )) && [[ "$REQUIRE_ALL_RADIOS" == "1" ]]; then finalize 1; fi

phase "H. CMS / API / NOW PLAYING"
CMS_HEALTH_FILE="$REPORT_DIR/cms-health.json"
CMS_HEALTH_CODE="$(curl -ksSL --connect-timeout 4 --max-time 12 -o "$CMS_HEALTH_FILE" -w '%{http_code}' "$PUBLIC_PORTAL/api/health" || true)"
CMS_HEALTH_OK=0
if [[ "$CMS_HEALTH_CODE" == "200" ]]; then
  set +e
  python3 - "$CMS_HEALTH_FILE" <<'PY'
import json,sys
x=json.load(open(sys.argv[1],encoding='utf-8'))
assert x.get('ok') is True
print('CMS_HEALTH_JSON=PASS')
PY
  JRC=$?
  set -e
  (( JRC == 0 )) && CMS_HEALTH_OK=1
fi
if (( CMS_HEALTH_OK == 1 )); then pass "cms_health" "HTTP=200 JSON ok"; else
  if [[ "$REQUIRE_CMS" == "1" ]]; then fatal "cms_health" "HTTP=$CMS_HEALTH_CODE ou JSON inválido"; else warn "cms_health" "HTTP=$CMS_HEALTH_CODE"; fi
fi

CMS_CONTENT_FILE="$REPORT_DIR/cms-content.json"
CMS_CONTENT_CODE="$(curl -ksSL --connect-timeout 4 --max-time 15 -o "$CMS_CONTENT_FILE" -w '%{http_code}' "$PUBLIC_PORTAL/api/content" || true)"
CMS_CONTENT_OK=0
if [[ "$CMS_CONTENT_CODE" == "200" ]]; then
  set +e
  python3 - "$CMS_CONTENT_FILE" <<'PY'
import json,sys
x=json.load(open(sys.argv[1],encoding='utf-8'))
ids={s.get('id') for s in x.get('stations',[])}
exp={'radioprincipal','radiopop','radiorock','radioclassicas','radiocountry'}
assert ids==exp,(ids,exp)
print('CMS_CONTENT_JSON=PASS stations=5')
PY
  JRC=$?
  set -e
  (( JRC == 0 )) && CMS_CONTENT_OK=1
fi
if (( CMS_CONTENT_OK == 1 )); then pass "cms_content" "5 emissoras"; else
  if [[ "$REQUIRE_CMS" == "1" ]]; then fatal "cms_content" "HTTP=$CMS_CONTENT_CODE ou conteúdo inválido"; else warn "cms_content" "HTTP=$CMS_CONTENT_CODE"; fi
fi

NOW_OK=0
for s in radioprincipal radiopop radiorock radioclassicas radiocountry; do
  NF="$REPORT_DIR/now-$s.json"
  NC="$(curl -ksSL --connect-timeout 3 --max-time 8 -o "$NF" -w '%{http_code}' "$PUBLIC_PLAYER/assets/now/$s.json" || true)"
  GOOD=0
  if [[ "$NC" == "200" ]]; then
    set +e
    python3 - "$NF" >/dev/null 2>&1 <<'PY'
import json,sys
x=json.load(open(sys.argv[1],encoding='utf-8'))
assert isinstance(x,dict)
PY
    JRC=$?
    set -e
    (( JRC == 0 )) && GOOD=1
  fi
  if (( GOOD == 1 )); then pass "now:$s" "JSON disponível"; NOW_OK=$((NOW_OK+1)); else warn "now:$s" "ainda não disponível/JSON inválido (HTTP=$NC); app usa fallback"; fi
done
if [[ "$NOW_PLAYING_STRICT" == "1" && "$NOW_OK" -ne 5 ]]; then fatal "now_playing" "$NOW_OK/5"; fi

phase "I. APK / LINKS DE LOJA (SE FORNECIDOS)"
if [[ -n "$APK_SOURCE" ]]; then
  [[ -f "$APK_SOURCE" ]] || fatal "apk_source" "arquivo não existe: $APK_SOURCE"
  set +e
  python3 - "$APK_SOURCE" <<'PY'
import sys,zipfile
assert zipfile.is_zipfile(sys.argv[1]), 'APK não é ZIP válido'
print('APK_ZIP=PASS')
PY
  APK_RC=$?
  set -e
  (( APK_RC == 0 )) || fatal "apk_source" "estrutura APK inválida"
  APK_SHA="$(sha256sum "$APK_SOURCE" | awk '{print $1}')"
  pass "apk_source" "sha256=$APK_SHA"
else
  warn "apk_source" "não fornecido; botão APK ficará pendente"
fi

if [[ -n "$PLAY_STORE_URL" ]]; then
  [[ "$PLAY_STORE_URL" == https://play.google.com/* ]] || warn "play_store_url" "URL não parece Google Play: $PLAY_STORE_URL"
  pass "play_store_url" "$PLAY_STORE_URL"
else
  warn "play_store_url" "não fornecida"
fi
if [[ -n "$APP_STORE_URL" ]]; then
  [[ "$APP_STORE_URL" == https://apps.apple.com/* ]] || warn "app_store_url" "URL não parece App Store: $APP_STORE_URL"
  pass "app_store_url" "$APP_STORE_URL"
else
  warn "app_store_url" "não fornecida"
fi

phase "J. DEPLOY SEGURO DA PÁGINA /app/"
DEPLOY="$REPO_DIR/scripts/deploy-download-page.sh"
ENV_ARGS=("VERSION=$VERSION" "PORTAL_ROOT=$PORTAL_ROOT" "PUBLIC_HOST=$PUBLIC_PORTAL")
[[ -n "$APK_SOURCE" ]] && ENV_ARGS+=("APK_SOURCE=$APK_SOURCE")
[[ -n "$PLAY_STORE_URL" ]] && ENV_ARGS+=("PLAY_STORE_URL=$PLAY_STORE_URL")
[[ -n "$APP_STORE_URL" ]] && ENV_ARGS+=("APP_STORE_URL=$APP_STORE_URL")
env "${ENV_ARGS[@]}" bash "$DEPLOY"
pass "download_page_deploy" "/app/"

phase "K. PÓS-VALIDAÇÃO / NÃO REGRESSÃO"
HOME_SHA_AFTER="$(sha256sum "$PORTAL_ROOT/index.html" | awk '{print $1}')"
if [[ "$HOME_SHA_BEFORE" == "$HOME_SHA_AFTER" ]]; then
  pass "portal_home_unchanged" "$HOME_SHA_AFTER"
else
  fatal "portal_home_unchanged" "HOME FOI ALTERADA: before=$HOME_SHA_BEFORE after=$HOME_SHA_AFTER"
fi

[[ -f "$PORTAL_ROOT/app/index.html" ]] || fatal "app_page_file" "ausente"
grep -q '<title>Baixar Radio Studio Sat</title>' "$PORTAL_ROOT/app/index.html" || fatal "app_page_content" "title ausente"
grep -q 'Cinco rádios' "$PORTAL_ROOT/app/index.html" || fatal "app_page_content" "texto principal ausente"
pass "app_page_file" "$PORTAL_ROOT/app/index.html"

LOCAL_APP_CODE="$(curl -ksS --resolve "$PORTAL_HOST:443:127.0.0.1" --connect-timeout 3 --max-time 10 -o "$REPORT_DIR/app-local.html" -w '%{http_code}' "$PUBLIC_PORTAL/app/?v=$TS" || true)"
[[ "$LOCAL_APP_CODE" == "200" ]] || fatal "app_origin" "HTTP=$LOCAL_APP_CODE"
pass "app_origin" "HTTP=200"

PUBLIC_APP_CODE="$(curl -ksSL --connect-timeout 5 --max-time 15 -o "$REPORT_DIR/app-public.html" -w '%{http_code}' "$PUBLIC_PORTAL/app/?v=$TS" || true)"
[[ "$PUBLIC_APP_CODE" == "200" ]] || fatal "app_public" "HTTP=$PUBLIC_APP_CODE"
grep -q 'Baixar Radio Studio Sat' "$REPORT_DIR/app-public.html" || fatal "app_public_content" "conteúdo inesperado"
pass "app_public" "HTTP=200 conteúdo ok"

nginx -t
pass "nginx_post_deploy" "ok"

if [[ -n "$APK_SOURCE" ]]; then
  APK_NAME="RadioStudioSat-v${VERSION}.apk"
  PUBLIC_APK="$PUBLIC_PORTAL/downloads/apps/$APK_NAME"
  DL="$REPORT_DIR/$APK_NAME"
  ACODE="$(curl -ksSL --connect-timeout 5 --max-time 60 -o "$DL" -w '%{http_code}' "$PUBLIC_APK" || true)"
  [[ "$ACODE" == "200" ]] || fatal "apk_public" "HTTP=$ACODE"
  DL_SHA="$(sha256sum "$DL" | awk '{print $1}')"
  [[ "$DL_SHA" == "$APK_SHA" ]] || fatal "apk_public_hash" "source=$APK_SHA public=$DL_SHA"
  pass "apk_public" "HTTP=200 sha256 match"
fi

# Health final das rádios: uma segunda amostra curta para detectar regressão durante deploy.
FINAL_RADIO_FAIL=0
for s in radioprincipal radiopop radiorock radioclassicas radiocountry; do
  FC="$(curl -ksSL --connect-timeout 3 --max-time 10 -o "$REPORT_DIR/final-$s.m3u8" -w '%{http_code}' "$PUBLIC_PLAYER/$s/index.m3u8" || true)"
  if [[ "$FC" == "200" ]] && grep -q '^#EXTM3U' "$REPORT_DIR/final-$s.m3u8"; then
    pass "final_hls:$s" "PASS"
  else
    fail "final_hls:$s" "HTTP=$FC"
    FINAL_RADIO_FAIL=$((FINAL_RADIO_FAIL+1))
  fi
done
if (( FINAL_RADIO_FAIL > 0 )) && [[ "$REQUIRE_ALL_RADIOS" == "1" ]]; then finalize 1; fi

phase "L. RESULTADO"
pass "deployment" "página=$PUBLIC_PORTAL/app/"
finalize 0
