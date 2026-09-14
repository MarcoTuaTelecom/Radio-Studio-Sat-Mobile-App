#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
umask 077

SRC_V71="${SRC_V71:-/var/backups/studiosat/PORTAL-GROK-BEAUTY-V71/20260911T224449Z}"
SRC_V6="${SRC_V6:-/var/backups/studiosat/PORTAL-GROK-BEAUTY-V6/20260911T220848Z}"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
BK="/var/backups/studiosat/RESTORE-PORTAL-KNOWN-GOOD-$TS"
PORTAL_HOST="www.radio.studiosatweb.com.br"
PLAYER_HOST="radio.studiosatweb.com.br"
SERVICE="/etc/systemd/system/studiosat-portal-cms.service"
MUTATED=0
SERVICE_WAS_ACTIVE=0
SERVICE_WAS_ENABLED=0

log(){ printf '%s\n' "$*"; }
fail(){ printf 'FATAL=%s\n' "$*" >&2; return 1; }
need(){ command -v "$1" >/dev/null 2>&1 || { echo "FATAL=MISSING_TOOL:$1" >&2; exit 70; }; }

[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo "FATAL=RUN_AS_ROOT" >&2; exit 77; }
for c in nginx systemctl curl tar cp mv rm mkdir sha256sum grep awk sed python3 readlink; do need "$c"; done

for f in \
  "$SRC_V71/old-custom-root.tar.gz" \
  "$SRC_V71/player-root-real.tar.gz" \
  "$SRC_V71/cms-opt.tar.gz" \
  "$SRC_V71/cms-data.tar.gz" \
  "$SRC_V71/cms-etc.tar.gz" \
  "$SRC_V71/service.file" \
  "$SRC_V71/portal-nginx.conf.file" \
  "$SRC_V71/live-portal-before.html" \
  "$SRC_V71/live-player-before.html" \
  "$SRC_V6/conf.d.before/studiosat-radio.conf"; do
  [[ -s "$f" ]] || { echo "FATAL=SOURCE_MISSING:$f" >&2; exit 71; }
done

mkdir -p "$BK"
exec > >(tee "$BK/RESTORE.log") 2>&1

echo "============================================================"
echo " STUDIO SAT - RESTAURACAO PORTAL CONHECIDO BOM"
echo " REFERENCIA: 11/09/2026 22:44 UTC (pre V7.1)"
echo " BACKUP_DESTA_RODADA=$BK"
echo "============================================================"

backup_tree(){
  local path="$1" name="$2"
  if [[ -e "$path" || -L "$path" ]]; then
    tar -C / -czpf "$BK/$name.tar.gz" "${path#/}"
  else
    : > "$BK/$name.ABSENT"
  fi
}

restore_tree_from_round_backup(){
  local path="$1" name="$2"
  rm -rf -- "$path"
  if [[ -f "$BK/$name.tar.gz" ]]; then
    tar -C / -xzpf "$BK/$name.tar.gz"
  fi
}

rollback(){
  local rc=$?
  trap - ERR EXIT
  if (( MUTATED == 1 )); then
    echo "ROLLBACK=START"
    rm -rf /etc/nginx
    tar -C / -xzpf "$BK/etc-nginx.tar.gz"
    restore_tree_from_round_backup /var/www/studiosat-radio web-studiosat-radio
    restore_tree_from_round_backup /var/www/studiosat-radio-player web-studiosat-radio-player
    restore_tree_from_round_backup /opt/studiosat-portal cms-opt
    restore_tree_from_round_backup /var/lib/studiosat-portal cms-data
    restore_tree_from_round_backup /etc/studiosat-portal cms-etc
    if [[ -f "$BK/service.file" ]]; then
      cp -a "$BK/service.file" "$SERVICE"
    else
      rm -f "$SERVICE"
    fi
    systemctl daemon-reload || true
    if (( SERVICE_WAS_ENABLED == 1 )); then systemctl enable studiosat-portal-cms.service >/dev/null 2>&1 || true; else systemctl disable studiosat-portal-cms.service >/dev/null 2>&1 || true; fi
    if (( SERVICE_WAS_ACTIVE == 1 )); then systemctl restart studiosat-portal-cms.service || true; else systemctl stop studiosat-portal-cms.service >/dev/null 2>&1 || true; fi
    if nginx -t; then systemctl reload nginx || true; fi
    echo "ROLLBACK=DONE"
  fi
  echo "BACKUP_DESTA_RODADA=$BK"
  exit "$rc"
}
trap rollback ERR EXIT

echo
echo "===== 0. GATE ANTES DE MEXER ====="
nginx -t || true
systemctl is-active --quiet nginx || fail "NGINX_NOT_ACTIVE"

LOCAL_BEFORE=0
for ch in radioprincipal radiopop radiorock radioclassicas radiocountry; do
  f="$BK/${ch}.before.m3u8"
  code="$(curl -sSL --connect-timeout 3 --max-time 15 -o "$f" -w '%{http_code}' "http://127.0.0.1:8888/$ch/index.m3u8" || true)"
  if [[ "$code" == 200 ]] && grep -q '^#EXTM3U' "$f"; then
    LOCAL_BEFORE=$((LOCAL_BEFORE+1)); echo "$ch BEFORE=PASS"
  else
    echo "$ch BEFORE=FAIL HTTP=$code"
  fi
done
[[ "$LOCAL_BEFORE" -eq 5 ]] || fail "RADIOS_LOCAL_BEFORE_${LOCAL_BEFORE}_OF_5"

echo
echo "===== 1. BACKUP OBRIGATORIO DESTA RODADA ====="
tar -C / -czpf "$BK/etc-nginx.tar.gz" etc/nginx
backup_tree /var/www/studiosat-radio web-studiosat-radio
backup_tree /var/www/studiosat-radio-player web-studiosat-radio-player
backup_tree /opt/studiosat-portal cms-opt
backup_tree /var/lib/studiosat-portal cms-data
backup_tree /etc/studiosat-portal cms-etc
if [[ -f "$SERVICE" ]]; then
  cp -a "$SERVICE" "$BK/service.file"
  systemctl is-active --quiet studiosat-portal-cms.service && SERVICE_WAS_ACTIVE=1 || true
  systemctl is-enabled --quiet studiosat-portal-cms.service && SERVICE_WAS_ENABLED=1 || true
fi
nginx -T > "$BK/nginx-T.before.txt" 2>&1 || true
sha256sum "$BK"/*.tar.gz > "$BK/SHA256SUMS.txt" 2>/dev/null || true
echo "ROUND_BACKUP=PASS"

MUTATED=1

echo
echo "===== 2. RESTAURANDO FRONTEND/PLAYER/CMS DA REFERENCIA ====="
rm -rf /var/www/studiosat-radio
rm -rf /var/www/studiosat-radio-player
rm -rf /opt/studiosat-portal
rm -rf /var/lib/studiosat-portal
rm -rf /etc/studiosat-portal

tar -C / -xzpf "$SRC_V71/old-custom-root.tar.gz"
tar -C / -xzpf "$SRC_V71/player-root-real.tar.gz"
tar -C / -xzpf "$SRC_V71/cms-opt.tar.gz"
tar -C / -xzpf "$SRC_V71/cms-data.tar.gz"
tar -C / -xzpf "$SRC_V71/cms-etc.tar.gz"
cp -a "$SRC_V71/service.file" "$SERVICE"

[[ -e /var/www/studiosat-radio/current ]] || fail "PORTAL_CURRENT_MISSING_AFTER_EXTRACT"
[[ -f /var/www/studiosat-radio/current/index.html ]] || fail "PORTAL_INDEX_MISSING_AFTER_EXTRACT"
[[ -f /var/www/studiosat-radio-player/index.html ]] || fail "PLAYER_INDEX_MISSING_AFTER_EXTRACT"

echo "CONTENT_RESTORE=PASS"

echo
echo "===== 3. RESTAURANDO PAR DE VHOSTS CONHECIDO BOM ====="
mkdir -p "$BK/nginx-conflicts"
while IFS= read -r f; do
  [[ -f "$f" ]] || continue
  case "$f" in
    /etc/nginx/conf.d/studiosat-radio.conf|/etc/nginx/conf.d/zz-studiosat-radio-portal.conf) continue ;;
  esac
  if grep -Eq 'server_name[^;]*(www\.)?radio\.studiosatweb\.com\.br' "$f"; then
    cp -a "$f" "$BK/nginx-conflicts/$(basename "$f")"
    mv "$f" "$f.disabled-recovery-$TS"
    echo "QUARANTINED=$f"
  fi
done < <(find /etc/nginx/conf.d -maxdepth 1 -type f -name '*.conf' -print | sort)

cp -a "$SRC_V6/conf.d.before/studiosat-radio.conf" /etc/nginx/conf.d/studiosat-radio.conf
cp -a "$SRC_V71/portal-nginx.conf.file" /etc/nginx/conf.d/zz-studiosat-radio-portal.conf

CERT=/etc/letsencrypt/live/studiosatweb-completo/fullchain.pem
KEY=/etc/letsencrypt/live/studiosatweb-completo/privkey.pem
[[ -r "$CERT" && -r "$KEY" ]] || fail "STUDIOSAT_COMPLETO_CERT_MISSING"

grep -qF "$CERT" /etc/nginx/conf.d/studiosat-radio.conf || fail "RADIO_CONF_CERT_NOT_EXPECTED"
grep -qF "$CERT" /etc/nginx/conf.d/zz-studiosat-radio-portal.conf || fail "PORTAL_CONF_CERT_NOT_EXPECTED"

nginx -t
systemctl reload nginx
systemctl is-active --quiet nginx
echo "NGINX_RESTORE=PASS"

echo
echo "===== 4. SUBINDO CMS DA REFERENCIA ====="
systemctl daemon-reload
systemctl enable studiosat-portal-cms.service >/dev/null 2>&1 || true
systemctl restart studiosat-portal-cms.service

CMS_OK=0
for _ in $(seq 1 20); do
  body="$(curl -fsS --connect-timeout 1 --max-time 2 http://127.0.0.1:8789/api/health 2>/dev/null || true)"
  if [[ "$body" == *'"ok": true'* ]]; then CMS_OK=1; break; fi
  sleep 1
done
[[ "$CMS_OK" -eq 1 ]] || { systemctl status studiosat-portal-cms.service --no-pager --full || true; journalctl -u studiosat-portal-cms.service -n 80 --no-pager || true; fail "CMS_NOT_READY"; }
echo "CMS=PASS"

echo
echo "===== 5. PROVA DO PORTAL E PLAYER ====="
PORTAL_BODY="$BK/portal.restored.html"
PLAYER_BODY="$BK/player.restored.html"
portal_code="$(curl -ksS --resolve "$PORTAL_HOST:443:127.0.0.1" -o "$PORTAL_BODY" -w '%{http_code}' "https://$PORTAL_HOST/" || true)"
player_code="$(curl -ksS --resolve "$PLAYER_HOST:443:127.0.0.1" -o "$PLAYER_BODY" -w '%{http_code}' "https://$PLAYER_HOST/" || true)"
echo "PORTAL_HTTP=$portal_code"
echo "PLAYER_HTTP=$player_code"
[[ "$portal_code" == 200 ]] || fail "PORTAL_HTTP_$portal_code"
[[ "$player_code" == 200 ]] || fail "PLAYER_HTTP_$player_code"

if cmp -s "$PORTAL_BODY" "$SRC_V71/live-portal-before.html"; then echo "PORTAL_EXACT_REFERENCE=YES"; else echo "PORTAL_EXACT_REFERENCE=NO_BUT_HTTP_200"; fi
if cmp -s "$PLAYER_BODY" "$SRC_V71/live-player-before.html"; then echo "PLAYER_EXACT_REFERENCE=YES"; else echo "PLAYER_EXACT_REFERENCE=NO_BUT_HTTP_200"; fi

api_code="$(curl -ksS --resolve "$PORTAL_HOST:443:127.0.0.1" -o "$BK/content.json" -w '%{http_code}' "https://$PORTAL_HOST/api/content" || true)"
echo "API_CONTENT_HTTP=$api_code"
[[ "$api_code" == 200 ]] || fail "API_CONTENT_HTTP_$api_code"
python3 - "$BK/content.json" <<'PY'
import json,sys
p=sys.argv[1]
d=json.load(open(p,encoding='utf-8'))
assert isinstance(d,dict)
print('API_JSON=PASS')
PY

echo
echo "===== 6. GARANTIA: 5 RADIOS CONTINUAM 5/5 ====="
LOCAL_AFTER=0
PUBLIC_AFTER=0
for ch in radioprincipal radiopop radiorock radioclassicas radiocountry; do
  lf="$BK/${ch}.after-local.m3u8"
  lcode="$(curl -sSL --connect-timeout 3 --max-time 15 -o "$lf" -w '%{http_code}' "http://127.0.0.1:8888/$ch/index.m3u8" || true)"
  if [[ "$lcode" == 200 ]] && grep -q '^#EXTM3U' "$lf"; then LOCAL_AFTER=$((LOCAL_AFTER+1)); fi

  pf="$BK/${ch}.after-public.m3u8"
  pcode="$(curl -ksSL --resolve "$PLAYER_HOST:443:127.0.0.1" --connect-timeout 3 --max-time 15 -o "$pf" -w '%{http_code}' "https://$PLAYER_HOST/$ch/index.m3u8" || true)"
  if [[ "$pcode" == 200 ]] && grep -q '^#EXTM3U' "$pf"; then PUBLIC_AFTER=$((PUBLIC_AFTER+1)); fi
  printf '%-18s local=%s public=%s\n' "$ch" "$lcode" "$pcode"
done
[[ "$LOCAL_AFTER" -eq 5 ]] || fail "RADIOS_LOCAL_AFTER_${LOCAL_AFTER}_OF_5"
[[ "$PUBLIC_AFTER" -eq 5 ]] || fail "RADIOS_PUBLIC_AFTER_${PUBLIC_AFTER}_OF_5"

echo
echo "===== 7. PUBLICO EXTERNO ====="
ext_code="$(curl -ksS --max-time 15 -o "$BK/public-portal.html" -w '%{http_code}' "https://$PORTAL_HOST/" || true)"
echo "PUBLIC_PORTAL_HTTP=$ext_code"
[[ "$ext_code" == 200 ]] || fail "PUBLIC_PORTAL_HTTP_$ext_code"

echo
echo "===== 8. ESTADO FINAL ====="
nginx -T > "$BK/nginx-T.after.txt" 2>&1
systemctl is-active nginx
systemctl is-active studiosat-portal-cms.service

echo "PORTAL_ONLINE=PASS"
echo "RADIOS_LOCAL=$LOCAL_AFTER/5"
echo "RADIOS_PUBLIC=$PUBLIC_AFTER/5"
echo "REFERENCE=2026-09-11T22:44:49Z_PRE_V71"
echo "BACKUP_DESTA_RODADA=$BK"
echo "URL=https://$PORTAL_HOST/"

trap - ERR EXIT
