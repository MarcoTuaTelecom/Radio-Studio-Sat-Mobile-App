#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
umask 077

SRC="/root/TPS-NS1-CLEANROOM-BACKUP-20260905T105542Z"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
BK="/var/backups/studiosat/PRE-DEEP-RESTORE-CLEANROOM-$TS"
MUTATED=0
CH=(radioprincipal radiopop radiorock radioclassicas radiocountry tvkids tvteens tvviva tvmaisjovem)

fail(){ echo "FATAL=$*" >&2; return 1; }
[[ ${EUID:-$(id -u)} -eq 0 ]] || exit 77
for x in "$SRC/nginx" "$SRC/bind" "$SRC/tpsmedia" "$SRC/systemd/etc/systemd/system"; do [[ -d "$x" ]] || { echo "FATAL=SOURCE_MISSING:$x"; exit 71; }; done
[[ -s "$SRC/tpsmedia/mediamtx/mediamtx.yml" ]] || { echo FATAL=MEDIAMTX_SOURCE_MISSING; exit 71; }
[[ -s "$SRC/systemd/etc/systemd/system/tps-mediamtx.service" ]] || { echo FATAL=MEDIAMTX_UNIT_SOURCE_MISSING; exit 71; }

mkdir -p "$BK"
exec > >(tee "$BK/RESTORE.log") 2>&1

echo "============================================================"
echo " NS1 - RESTORE PROFUNDO CLEANROOM"
echo " SOURCE=$SRC"
echo " BACKUP_DESTA_RODADA=$BK"
echo " /srv/tpsmedia/repository SERA PRESERVADO"
echo "============================================================"

backup(){ local p="$1" n="$2"; if [[ -e "$p" || -L "$p" ]]; then tar -C / -czpf "$BK/$n.tar.gz" "${p#/}"; else : > "$BK/$n.ABSENT"; fi; }
restore(){ local p="$1" n="$2"; rm -rf -- "$p"; [[ -f "$BK/$n.tar.gz" ]] && tar -C / -xzpf "$BK/$n.tar.gz" || true; }

rollback(){
  rc=$?; trap - ERR EXIT
  if (( MUTATED )); then
    echo "ROLLBACK=START"
    restore /etc/nginx etc-nginx
    restore /etc/bind etc-bind
    restore /etc/tpsmedia etc-tpsmedia
    restore /etc/systemd/system etc-systemd
    systemctl daemon-reload || true
    nginx -t >/dev/null 2>&1 && systemctl restart nginx || true
    systemctl restart tps-mediamtx.service 2>/dev/null || true
    systemctl restart bind9 2>/dev/null || systemctl restart named 2>/dev/null || true
    for c in "${CH[@]}"; do [[ -f "$BK/active-$c" ]] && systemctl restart "tps-$c-playout.service" 2>/dev/null || true; done
    [[ -f "$BK/active-cms" ]] && systemctl restart studiosat-portal-cms.service 2>/dev/null || true
    echo "ROLLBACK=DONE"
  fi
  echo "BACKUP_DESTA_RODADA=$BK"
  exit "$rc"
}
trap rollback ERR EXIT

echo "===== 1. PROVA DA FONTE ====="
find "$SRC" -xdev -type f -printf '%s | %TY-%Tm-%Td %TH:%TM:%TS | %p\n' | sort > "$BK/source-files.txt"
echo "SOURCE_FILES=$(wc -l < "$BK/source-files.txt")"
echo "SOURCE_SIZE=$(du -sh "$SRC" | awk '{print $1}')"
sha256sum "$SRC/tpsmedia/mediamtx/mediamtx.yml" "$SRC/systemd/etc/systemd/system/tps-mediamtx.service"

echo "===== 2. BACKUP OBRIGATORIO DO ESTADO ATUAL ====="
backup /etc/nginx etc-nginx
backup /etc/bind etc-bind
backup /etc/tpsmedia etc-tpsmedia
backup /etc/systemd/system etc-systemd
nginx -T > "$BK/nginx-T.before.txt" 2>&1 || true
for c in "${CH[@]}"; do systemctl is-active --quiet "tps-$c-playout.service" 2>/dev/null && : > "$BK/active-$c" || true; done
systemctl is-active --quiet studiosat-portal-cms.service 2>/dev/null && : > "$BK/active-cms" || true
find /srv/tpsmedia/repository/channels -maxdepth 3 -type f -printf '%s | %p\n' 2>/dev/null | sort > "$BK/media-before.txt" || true
sha256sum "$BK"/*.tar.gz > "$BK/SHA256SUMS.txt"
echo "ROUND_BACKUP=PASS"

MUTATED=1

echo "===== 3. RETIRANDO CAMADAS POSTERIORES A CLEANROOM ====="
for c in "${CH[@]}"; do systemctl disable --now "tps-$c-playout.service" >/dev/null 2>&1 || true; done
systemctl disable --now studiosat-portal-cms.service >/dev/null 2>&1 || true

echo "===== 4. NGINX CLEANROOM ====="
if [[ -f "$SRC/nginx/nginx.conf" ]]; then
  rm -rf /etc/nginx; mkdir -p /etc/nginx; cp -a "$SRC/nginx/." /etc/nginx/
  echo NGINX_MODE=FULL
else
  [[ -d "$SRC/nginx/conf.d" ]] || fail NGINX_CONF_D_SOURCE_MISSING
  rm -rf /etc/nginx/conf.d; mkdir -p /etc/nginx/conf.d; cp -a "$SRC/nginx/conf.d/." /etc/nginx/conf.d/
  echo NGINX_MODE=CONF_D_ONLY
fi

echo "===== 5. BIND CLEANROOM ====="
rm -rf /etc/bind; mkdir -p /etc/bind; cp -a "$SRC/bind/." /etc/bind/

echo "===== 6. TPSMEDIA / MEDIAMTX CLEANROOM ====="
rm -rf /etc/tpsmedia; mkdir -p /etc/tpsmedia; cp -a "$SRC/tpsmedia/." /etc/tpsmedia/

echo "===== 7. SYSTEMD CLEANROOM ====="
for c in "${CH[@]}"; do rm -f "/etc/systemd/system/tps-$c-playout.service"; rm -rf "/etc/systemd/system/tps-$c-playout.service.d"; done
rm -f /etc/systemd/system/studiosat-portal-cms.service
rm -rf /etc/systemd/system/studiosat-portal-cms.service.d
cp -a "$SRC/systemd/etc/systemd/system/." /etc/systemd/system/
systemctl daemon-reload

echo "===== 8. VALIDACAO ====="
nginx -t
[[ -s /etc/tpsmedia/mediamtx/mediamtx.yml ]] || fail MEDIAMTX_RESTORE_EMPTY
[[ -s /etc/systemd/system/tps-mediamtx.service ]] || fail MEDIAMTX_UNIT_RESTORE_EMPTY
if command -v named-checkconf >/dev/null 2>&1; then named-checkconf; echo BIND_CHECK=PASS; fi
if [[ -f /etc/bind/zones/db.studiosatweb.com.br ]] && command -v named-checkzone >/dev/null 2>&1; then named-checkzone studiosatweb.com.br /etc/bind/zones/db.studiosatweb.com.br; fi

echo "===== 9. SUBINDO FUNDACAO ====="
systemctl restart tps-mediamtx.service
systemctl is-active --quiet tps-mediamtx.service
systemctl restart nginx
systemctl is-active --quiet nginx
if systemctl list-unit-files | grep -q '^bind9.service'; then systemctl restart bind9; systemctl is-active --quiet bind9; elif systemctl list-unit-files | grep -q '^named.service'; then systemctl restart named; systemctl is-active --quiet named; fi

echo "===== 10. PROVA DE PRESERVACAO DA MIDIA ====="
P=0
for c in "${CH[@]}"; do [[ -d "/srv/tpsmedia/repository/channels/$c" ]] && { P=$((P+1)); echo "$c=PRESERVED"; } || echo "$c=ABSENT"; done

echo "===== FINAL ====="
echo "DEEP_RESTORE=PASS"
echo "FOUNDATION_REFERENCE=TPS-NS1-CLEANROOM-BACKUP-20260905T105542Z"
echo "MEDIA_CHANNEL_DIRS_PRESERVED=$P/9"
echo "MEDIA_REPOSITORY_PRESERVED=YES"
echo "BACKUP_DESTA_RODADA=$BK"
echo "NEXT=RECONSTRUIR_9_EMISSORAS_A_PARTIR_DESTA_FUNDACAO"
trap - ERR EXIT
