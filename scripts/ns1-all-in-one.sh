#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

VERSION="${VERSION:-1.0.0}"
REPO_DIR="${REPO_DIR:-/root/Radio-Studio-Sat-Mobile-App}"
REPO_REMOTE="${REPO_REMOTE:-git@github.com:MarcoTuaTelecom/Radio-Studio-Sat-Mobile-App.git}"
SSH_KEY="${SSH_KEY:-/root/.ssh/id_ed25519_studiosat_mobile}"
PORTAL_ROOT="${PORTAL_ROOT:-/var/www/studiosat-radio-portal}"
PORTAL_HOST="${PORTAL_HOST:-www.radio.studiosatweb.com.br}"
PLAYER_HOST="${PLAYER_HOST:-radio.studiosatweb.com.br}"
APK_SOURCE="${APK_SOURCE:-}"
PLAY_STORE_URL="${PLAY_STORE_URL:-}"
APP_STORE_URL="${APP_STORE_URL:-}"
RUN_NODE_VALIDATION="${RUN_NODE_VALIDATION:-auto}"
STRICT_NODE="${STRICT_NODE:-0}"
REQUIRE_ALL_RADIOS="${REQUIRE_ALL_RADIOS:-1}"
REQUIRE_CMS="${REQUIRE_CMS:-1}"
NOW_PLAYING_STRICT="${NOW_PLAYING_STRICT:-0}"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
REPORT_DIR="${REPORT_BASE:-/var/log/studiosat-mobile}/ns1-$TS"
REPORT="$REPORT_DIR/REPORT.txt"
SUMMARY="$REPORT_DIR/summary.tsv"
LOCK_FILE="${LOCK_FILE:-/var/lock/studiosat-mobile-ns1.lock}"
PUBLIC_PORTAL="https://$PORTAL_HOST"
PUBLIC_PLAYER="https://$PLAYER_HOST"

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
finish(){
  local rc="${1:-0}"
  printf 'check\tstatus\tdetail\n' > "$SUMMARY"
  local row
  for row in "${RESULTS[@]:-}"; do printf '%b\n' "$row" >> "$SUMMARY"; done
  printf '\n===== RESUMO =====\nPASS=%d WARN=%d FAIL=%d\n' "$PASS_COUNT" "$WARN_COUNT" "$FAIL_COUNT"
  printf 'HEAD=%s\n' "$(git -C "$REPO_DIR" rev-parse HEAD 2>/dev/null || echo unavailable)"
  printf 'REPORT=%s\nSUMMARY=%s\n' "$REPORT" "$SUMMARY"
  if (( FAIL_COUNT > 0 || rc != 0 )); then echo 'NS1_MOBILE_RESULT=FAIL'; exit 1; fi
  if (( WARN_COUNT > 0 )); then echo 'NS1_MOBILE_RESULT=PASS_WITH_WARNINGS'; else echo 'NS1_MOBILE_RESULT=PASS'; fi
}
fatal(){ fail "$1" "${2:-}"; finish 1; }
need(){ command -v "$1" >/dev/null 2>&1 || fatal "tool:$1" "comando ausente"; }

trap 'rc=$?; if (( rc != 0 )); then fail "unhandled_error" "rc=$rc line=${BASH_LINENO[0]:-?} cmd=${BASH_COMMAND:-?}"; finish "$rc"; fi' ERR

phase "A. HOST"
[[ ${EUID:-$(id -u)} -eq 0 ]] || fatal root "execute como root"
pass root uid=0
for c in bash git ssh ssh-keygen curl python3 grep awk sha256sum flock nginx; do need "$c"; done
pass base_tools ok
exec 9>"$LOCK_FILE"
flock -n 9 || fatal lock "outra execução ativa"
pass lock "$LOCK_FILE"
HOSTNAME_NOW="$(hostname -f 2>/dev/null || hostname)"
[[ "$HOSTNAME_NOW" == ns1* ]] && pass host_identity "$HOSTNAME_NOW" || warn host_identity "$HOSTNAME_NOW"

phase "B. CHAVE SSH / GITHUB"
[[ -f "$SSH_KEY" ]] || fatal ssh_private_key "$SSH_KEY ausente"
[[ -f "$SSH_KEY.pub" ]] || fatal ssh_public_key "$SSH_KEY.pub ausente"
chmod 0600 "$SSH_KEY"; chmod 0644 "$SSH_KEY.pub"
SSH_FP="$(ssh-keygen -lf "$SSH_KEY.pub" | awk '{print $2}')"
pass ssh_key "$SSH_FP"
SSH_ARGS=(-i "$SSH_KEY" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new)
SSH_STRING="ssh -i $SSH_KEY -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new"
set +e
SSH_TEST_OUT="$(ssh "${SSH_ARGS[@]}" -T git@github.com 2>&1)"
SSH_TEST_RC=$?
set -e
printf '%s\n' "$SSH_TEST_OUT"
grep -qi 'successfully authenticated' <<<"$SSH_TEST_OUT" || fatal github_ssh "rc=$SSH_TEST_RC"
pass github_ssh "deploy key autenticada"

phase "C. REPOSITORIO"
if [[ ! -d "$REPO_DIR/.git" ]]; then
  GIT_SSH_COMMAND="$SSH_STRING" git clone "$REPO_REMOTE" "$REPO_DIR"
  pass repo_clone "$REPO_DIR"
else
  pass repo_exists "$REPO_DIR"
fi

git -C "$REPO_DIR" config core.sshCommand "$SSH_STRING"
[[ -z "$(git -C "$REPO_DIR" status --porcelain)" ]] || fatal git_worktree "há alterações locais"
pass git_worktree clean
OLD_HEAD="$(git -C "$REPO_DIR" rev-parse HEAD)"
git -C "$REPO_DIR" fetch origin main
git -C "$REPO_DIR" checkout -q main
git -C "$REPO_DIR" pull --ff-only origin main
NEW_HEAD="$(git -C "$REPO_DIR" rev-parse HEAD)"
pass git_sync "$NEW_HEAD"
if [[ "$OLD_HEAD" != "$NEW_HEAD" && "${STUDIOSAT_REEXECED:-0}" != 1 ]]; then
  echo "Repositorio atualizado; reiniciando com a versao nova..."
  exec env STUDIOSAT_REEXECED=1 VERSION="$VERSION" REPO_DIR="$REPO_DIR" SSH_KEY="$SSH_KEY" PORTAL_ROOT="$PORTAL_ROOT" PORTAL_HOST="$PORTAL_HOST" PLAYER_HOST="$PLAYER_HOST" APK_SOURCE="$APK_SOURCE" PLAY_STORE_URL="$PLAY_STORE_URL" APP_STORE_URL="$APP_STORE_URL" RUN_NODE_VALIDATION="$RUN_NODE_VALIDATION" STRICT_NODE="$STRICT_NODE" REQUIRE_ALL_RADIOS="$REQUIRE_ALL_RADIOS" REQUIRE_CMS="$REQUIRE_CMS" NOW_PLAYING_STRICT="$NOW_PLAYING_STRICT" bash "$REPO_DIR/scripts/ns1-all-in-one.sh"
fi

phase "D. FONTES"
EXPECTED=(App.tsx app.json package.json eas.json tsconfig.json src/config/stations.ts src/services/api.ts src/types/index.ts src/components/MediaCarousel.tsx src/components/StationSelector.tsx src/components/VuMeter.tsx scripts/build-release.sh scripts/deploy-download-page.sh scripts/ns1-all-in-one.sh web/download/index.html docs/API_CONTRACT.md docs/PUBLISHING.md docs/DOWNLOAD_PAGE_DEPLOY.md assets/icon.png assets/adaptive-icon.png assets/splash.png)
for f in "${EXPECTED[@]}"; do [[ -f "$REPO_DIR/$f" ]] || fatal source_file "ausente: $f"; done
pass source_files "${#EXPECTED[@]} arquivos criticos"
bash -n "$REPO_DIR/scripts/build-release.sh"
bash -n "$REPO_DIR/scripts/deploy-download-page.sh"
bash -n "$REPO_DIR/scripts/ns1-all-in-one.sh"
pass shell_syntax ok
python3 - "$REPO_DIR" <<'PY'
import json,sys,pathlib
r=pathlib.Path(sys.argv[1])
for n in ('app.json','package.json','eas.json'): json.loads((r/n).read_text())
a=json.loads((r/'app.json').read_text())['expo']
assert a['android']['package']=='br.com.studiosatweb.radio'
assert a['ios']['bundleIdentifier']=='br.com.studiosatweb.radio'
PY
pass json_config br.com.studiosatweb.radio
for s in radioprincipal radiopop radiorock radioclassicas radiocountry; do grep -q "$s" "$REPO_DIR/src/config/stations.ts" || fatal station_config "$s ausente"; done
pass station_config "5 emissoras"

phase "E. NODE / EXPO"
DO_NODE=0
case "$RUN_NODE_VALIDATION" in
  1|yes|true) DO_NODE=1;;
  0|no|false) DO_NODE=0;;
  auto) command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1 && DO_NODE=1 || true;;
  *) fatal RUN_NODE_VALIDATION "valor invalido";;
esac
if (( DO_NODE )); then
  set +e
  (cd "$REPO_DIR" && npm install --no-audit --no-fund)
  NRC=$?
  set -e
  if (( NRC == 0 )); then
    pass npm_install ok
    set +e; (cd "$REPO_DIR" && npm run typecheck); TRC=$?; set -e
    (( TRC == 0 )) && pass typecheck ok || { [[ "$STRICT_NODE" == 1 ]] && fatal typecheck "rc=$TRC" || warn typecheck "rc=$TRC"; }
    set +e; (cd "$REPO_DIR" && npx --yes expo-doctor); ERC=$?; set -e
    (( ERC == 0 )) && pass expo_doctor ok || { [[ "$STRICT_NODE" == 1 ]] && fatal expo_doctor "rc=$ERC" || warn expo_doctor "rc=$ERC"; }
  else
    [[ "$STRICT_NODE" == 1 ]] && fatal npm_install "rc=$NRC" || warn npm_install "rc=$NRC"
  fi
else
  warn node_validation "ignorada"
fi

phase "F. NGINX / PORTAL"
[[ -f "$PORTAL_ROOT/index.html" ]] || fatal portal_home "ausente"
HOME_SHA_BEFORE="$(sha256sum "$PORTAL_ROOT/index.html" | awk '{print $1}')"
nginx -t
pass nginx_config ok
command -v systemctl >/dev/null 2>&1 && { systemctl is-active --quiet nginx || fatal nginx_service inactive; pass nginx_service active; }
PCODE="$(curl -ksSL --connect-timeout 5 --max-time 15 -o "$REPORT_DIR/portal.html" -w '%{http_code}' "$PUBLIC_PORTAL/" || true)"
[[ "$PCODE" == 200 ]] || fatal portal_public "HTTP=$PCODE"
pass portal_public HTTP=200

phase "G. CINCO RADIOS"
RADIO_FAIL=0
for s in radioprincipal radiopop radiorock radioclassicas radiocountry; do
  F="$REPORT_DIR/$s.m3u8"
  C="$(curl -ksSL --connect-timeout 4 --max-time 15 -o "$F" -w '%{http_code}' "$PUBLIC_PLAYER/$s/index.m3u8" || true)"
  if [[ "$C" == 200 ]] && grep -q '^#EXTM3U' "$F"; then pass "hls:$s" HTTP=200; else fail "hls:$s" "HTTP=$C"; RADIO_FAIL=$((RADIO_FAIL+1)); fi
done
(( RADIO_FAIL == 0 )) || [[ "$REQUIRE_ALL_RADIOS" != 1 ]] || finish 1

phase "H. CMS"
HFILE="$REPORT_DIR/health.json"
HC="$(curl -ksSL --connect-timeout 4 --max-time 12 -o "$HFILE" -w '%{http_code}' "$PUBLIC_PORTAL/api/health" || true)"
HOK=0
if [[ "$HC" == 200 ]]; then set +e; python3 - "$HFILE" <<'PY'
import json,sys
assert json.load(open(sys.argv[1])).get('ok') is True
PY
HRC=$?; set -e; (( HRC == 0 )) && HOK=1; fi
if (( HOK )); then pass cms_health HTTP=200; else [[ "$REQUIRE_CMS" == 1 ]] && fatal cms_health "HTTP=$HC" || warn cms_health "HTTP=$HC"; fi
CFILE="$REPORT_DIR/content.json"
CC="$(curl -ksSL --connect-timeout 4 --max-time 15 -o "$CFILE" -w '%{http_code}' "$PUBLIC_PORTAL/api/content" || true)"
COK=0
if [[ "$CC" == 200 ]]; then set +e; python3 - "$CFILE" <<'PY'
import json,sys
x=json.load(open(sys.argv[1])); ids={s.get('id') for s in x.get('stations',[])}
assert ids=={'radioprincipal','radiopop','radiorock','radioclassicas','radiocountry'}
PY
CRC=$?; set -e; (( CRC == 0 )) && COK=1; fi
if (( COK )); then pass cms_content "5 emissoras"; else [[ "$REQUIRE_CMS" == 1 ]] && fatal cms_content "HTTP=$CC" || warn cms_content "HTTP=$CC"; fi

NOW_OK=0
for s in radioprincipal radiopop radiorock radioclassicas radiocountry; do
  NF="$REPORT_DIR/now-$s.json"; NC="$(curl -ksSL --connect-timeout 3 --max-time 8 -o "$NF" -w '%{http_code}' "$PUBLIC_PLAYER/assets/now/$s.json" || true)"
  GOOD=0
  if [[ "$NC" == 200 ]]; then set +e; python3 - "$NF" >/dev/null 2>&1 <<'PY'
import json,sys
assert isinstance(json.load(open(sys.argv[1])),dict)
PY
NRC=$?; set -e; (( NRC == 0 )) && GOOD=1; fi
  if (( GOOD )); then pass "now:$s" ok; NOW_OK=$((NOW_OK+1)); else warn "now:$s" "HTTP=$NC fallback"; fi
done
[[ "$NOW_PLAYING_STRICT" != 1 || "$NOW_OK" == 5 ]] || fatal now_playing "$NOW_OK/5"

phase "I. APK / LOJAS"
APK_SHA=""
if [[ -n "$APK_SOURCE" ]]; then
  [[ -f "$APK_SOURCE" ]] || fatal apk_source "ausente"
  set +e; python3 - "$APK_SOURCE" <<'PY'
import sys,zipfile
assert zipfile.is_zipfile(sys.argv[1])
PY
ARC=$?; set -e
  (( ARC == 0 )) || fatal apk_source invalido
  APK_SHA="$(sha256sum "$APK_SOURCE" | awk '{print $1}')"
  pass apk_source "$APK_SHA"
else warn apk_source "nao fornecido"; fi
[[ -n "$PLAY_STORE_URL" ]] && pass play_store_url "$PLAY_STORE_URL" || warn play_store_url "nao fornecida"
[[ -n "$APP_STORE_URL" ]] && pass app_store_url "$APP_STORE_URL" || warn app_store_url "nao fornecida"

phase "J. DEPLOY /app/"
ENV_ARGS=("VERSION=$VERSION" "PORTAL_ROOT=$PORTAL_ROOT" "PUBLIC_HOST=$PUBLIC_PORTAL")
[[ -n "$APK_SOURCE" ]] && ENV_ARGS+=("APK_SOURCE=$APK_SOURCE")
[[ -n "$PLAY_STORE_URL" ]] && ENV_ARGS+=("PLAY_STORE_URL=$PLAY_STORE_URL")
[[ -n "$APP_STORE_URL" ]] && ENV_ARGS+=("APP_STORE_URL=$APP_STORE_URL")
env "${ENV_ARGS[@]}" bash "$REPO_DIR/scripts/deploy-download-page.sh"
pass download_page_deploy /app/

phase "K. POS-VALIDACAO"
HOME_SHA_AFTER="$(sha256sum "$PORTAL_ROOT/index.html" | awk '{print $1}')"
[[ "$HOME_SHA_BEFORE" == "$HOME_SHA_AFTER" ]] || fatal portal_home_unchanged "home alterada"
pass portal_home_unchanged "$HOME_SHA_AFTER"
[[ -f "$PORTAL_ROOT/app/index.html" ]] || fatal app_page_file ausente
grep -q 'Baixar Radio Studio Sat' "$PORTAL_ROOT/app/index.html" || fatal app_page_content invalido
AC="$(curl -ksSL --connect-timeout 5 --max-time 15 -o "$REPORT_DIR/app.html" -w '%{http_code}' "$PUBLIC_PORTAL/app/?v=$TS" || true)"
[[ "$AC" == 200 ]] || fatal app_public "HTTP=$AC"
pass app_public HTTP=200
nginx -t
pass nginx_post_deploy ok

FINAL_FAIL=0
for s in radioprincipal radiopop radiorock radioclassicas radiocountry; do
  FC="$(curl -ksSL --connect-timeout 3 --max-time 10 -o "$REPORT_DIR/final-$s.m3u8" -w '%{http_code}' "$PUBLIC_PLAYER/$s/index.m3u8" || true)"
  if [[ "$FC" == 200 ]] && grep -q '^#EXTM3U' "$REPORT_DIR/final-$s.m3u8"; then pass "final_hls:$s" PASS; else fail "final_hls:$s" "HTTP=$FC"; FINAL_FAIL=$((FINAL_FAIL+1)); fi
done
(( FINAL_FAIL == 0 )) || [[ "$REQUIRE_ALL_RADIOS" != 1 ]] || finish 1

pass deployment "$PUBLIC_PORTAL/app/"
finish 0
