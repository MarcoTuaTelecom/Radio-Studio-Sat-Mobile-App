#!/usr/bin/env bash
# Studio Sat / TPS - raio X forense + recuperacao conservadora do NS1
# Nao apaga midia. Faz snapshot antes de qualquer mudanca e so reinicia servicos
# relacionados a canais quebrados. Rollback de nginx e tentado apenas se melhorar HLS.
set -uo pipefail
IFS=$'\n\t'

TS="$(date -u +%Y%m%dT%H%M%SZ)"
ROOT="${RECOVERY_ROOT:-/var/log/studiosat-recovery}"
OUT="$ROOT/$TS"
REPORT="$OUT/REPORT.txt"
mkdir -p "$OUT"
exec > >(tee -a "$REPORT") 2>&1

RADIO_HOST="${RADIO_HOST:-radio.studiosatweb.com.br}"
PORTAL_HOST="${PORTAL_HOST:-www.radio.studiosatweb.com.br}"
RADIOS=(radioprincipal radiopop radiorock radioclassicas radiocountry)
PASS_BEFORE=0
PASS_AFTER=0
CHANGES=0
UNRESOLVED=0

section(){ printf '\n\n===== %s =====\n' "$*"; }
info(){ printf 'INFO  %s\n' "$*"; }
pass(){ printf 'PASS  %s\n' "$*"; }
warn(){ printf 'WARN  %s\n' "$*"; }
fail(){ printf 'FAIL  %s\n' "$*"; UNRESOLVED=$((UNRESOLVED+1)); }
have(){ command -v "$1" >/dev/null 2>&1; }

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then echo 'FATAL: execute como root' >&2; exit 77; fi
for c in bash date hostname systemctl journalctl ps find grep awk sed sort tail head curl nginx tar cp mv sha256sum stat python3; do
  have "$c" || { echo "FATAL: comando ausente: $c" >&2; exit 70; }
done

http_code(){ curl -ksS -L --max-redirs 6 --connect-timeout 5 --max-time 15 -o /dev/null -w '%{http_code}' "$1" 2>/dev/null || true; }

hls_check(){
  local ch="$1" url h b jar code first nexturl code2
  url="https://$RADIO_HOST/$ch/index.m3u8"
  h="$(mktemp)"; b="$(mktemp)"; jar="$(mktemp)"
  code="$(curl -ksS -L --max-redirs 8 --connect-timeout 5 --max-time 20 -D "$h" -o "$b" -c "$jar" -b "$jar" -w '%{http_code}' "$url" 2>/dev/null || true)"
  if [[ "$code" != "200" ]] || ! grep -q '#EXTM3U' "$b"; then rm -f "$h" "$b" "$jar"; return 1; fi
  first="$(awk 'NF && $0 !~ /^#/ {gsub(/\r/,""); print; exit}' "$b")"
  if [[ -n "$first" ]]; then
    nexturl="$(python3 - "$url" "$first" <<'PY' 2>/dev/null || true
import sys
from urllib.parse import urljoin
print(urljoin(sys.argv[1], sys.argv[2]))
PY
)"
    if [[ -n "$nexturl" ]]; then
      code2="$(curl -ksS -L --max-redirs 8 --connect-timeout 5 --max-time 20 -o /dev/null -c "$jar" -b "$jar" -w '%{http_code}' "$nexturl" 2>/dev/null || true)"
      [[ "$code2" =~ ^(200|206)$ ]] || { rm -f "$h" "$b" "$jar"; return 1; }
    fi
  fi
  rm -f "$h" "$b" "$jar"; return 0
}

radio_matrix(){
  local label="$1" ch ok=0
  section "HLS RADIO - $label"
  for ch in "${RADIOS[@]}"; do if hls_check "$ch"; then echo "PASS  $ch"; ok=$((ok+1)); else echo "FAIL  $ch"; fi; done
  echo "RADIO_PASS_${label// /_}=$ok/5"; RADIO_MATRIX_COUNT="$ok"
}

find_channel_units(){
  local ch="$1"
  grep -RIl --include='*.service' -- "$ch" /etc/systemd/system /usr/lib/systemd/system /lib/systemd/system 2>/dev/null | while IFS= read -r f; do basename "$f"; done | sort -u
}

restart_unit_safe(){
  local unit="$1"; [[ "$unit" == *.service ]] || return 0
  echo "ACTION restart $unit"; systemctl reset-failed "$unit" >/dev/null 2>&1 || true
  if systemctl restart "$unit"; then pass "reiniciado $unit"; CHANGES=$((CHANGES+1)); else fail "nao consegui reiniciar $unit"; systemctl status "$unit" --no-pager -l || true; journalctl -u "$unit" -n 80 --no-pager || true; fi
}

channel_has_fresh_hls(){
  local ch="$1"; find /var/www /srv -xdev -type f -path "*$ch*" -name '*.m3u8' -mmin -10 -print -quit 2>/dev/null | grep -q .
}

maybe_regenerate_playlist(){
  local ch="$1" base="/srv/tpsmedia/repository/channels/$ch" gen="/usr/local/sbin/tps-generate-playlist"
  [[ -d "$base" && -x "$gen" && -d "$base/ready" ]] || return 0
  find "$base/ready" -maxdepth 1 -type f -print -quit 2>/dev/null | grep -q . || return 0
  if grep -Eq '\$\{?1([}:]|\b)' "$gen" 2>/dev/null; then
    echo "ACTION playlist $ch via $gen"
    if "$gen" "$ch"; then pass "playlist regenerada para $ch"; CHANGES=$((CHANGES+1)); else warn "gerador retornou erro para $ch"; fi
  else warn "$gen existe, mas formato de argumento nao foi confirmado; nao executei automaticamente"; fi
}

nginx_error_file(){
  local out; out="$(nginx -t 2>&1 || true)"; printf '%s\n' "$out" > "$OUT/nginx-test-error.txt"; printf '%s\n' "$out" | grep -oE '/etc/nginx/[^ :]+\.conf' | head -1 || true
}

recover_nginx_syntax_if_needed(){
  nginx -t >/dev/null 2>&1 && return 0
  section "RECUPERACAO NGINX - SINTAXE"
  local bad candidate; bad="$(nginx_error_file)"
  [[ -n "$bad" && -f "$bad" ]] || { fail "nginx invalido e arquivo causador nao identificado"; return 1; }
  cp -a "$bad" "$OUT/$(basename "$bad").broken-$TS"
  mapfile -t candidates < <(find "$(dirname "$bad")" -maxdepth 1 -type f -name "$(basename "$bad").bak-*" -printf '%T@ %p\n' 2>/dev/null | sort -nr | awk '{print $2}')
  ((${#candidates[@]})) || { fail "sem backup para $bad"; return 1; }
  for candidate in "${candidates[@]}"; do
    echo "TRY_BACKUP=$candidate"; cp -a "$candidate" "$bad"
    if nginx -t; then systemctl reload nginx || systemctl restart nginx || true; pass "nginx recuperado com $candidate"; CHANGES=$((CHANGES+1)); return 0; fi
  done
  cp -a "$OUT/$(basename "$bad").broken-$TS" "$bad"; fail "nenhum backup validou; original quebrado preservado"; return 1
}

try_radio_nginx_backups_if_needed(){
  local current="/etc/nginx/conf.d/studiosat-radio.conf"; [[ -f "$current" ]] || { warn "$current nao existe"; return 0; }
  radio_matrix "PRE_NGINX_ROLLBACK"; local baseline="$RADIO_MATRIX_COUNT"; (( baseline < 5 )) || return 0
  mapfile -t candidates < <(find /etc/nginx/conf.d -maxdepth 1 -type f -name 'studiosat-radio.conf.bak-*' -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -12 | awk '{print $2}')
  ((${#candidates[@]})) || { warn "sem backups studiosat-radio.conf para testar"; return 0; }
  section "TESTE CONTROLADO DE BACKUPS DO VHOST RADIO"
  cp -a "$current" "$OUT/studiosat-radio.conf.before-backup-test"
  local best="$baseline" bestfile="" cand count
  for cand in "${candidates[@]}"; do
    echo "TRY=$cand"; cp -a "$cand" "$current"
    if ! nginx -t >/dev/null 2>&1; then echo "SKIP invalid nginx"; continue; fi
    systemctl reload nginx >/dev/null 2>&1 || continue; sleep 1; count=0
    for ch in "${RADIOS[@]}"; do hls_check "$ch" && count=$((count+1)); done
    echo "BACKUP_SCORE=$count/5 $cand"
    if (( count > best )); then best="$count"; bestfile="$cand"; cp -a "$cand" "$OUT/studiosat-radio.conf.best"; fi
    (( best == 5 )) && break
  done
  if (( best > baseline )) && [[ -f "$OUT/studiosat-radio.conf.best" ]]; then
    cp -a "$OUT/studiosat-radio.conf.best" "$current"; nginx -t && systemctl reload nginx
    pass "vhost radio restaurado; HLS melhorou $baseline/5 -> $best/5 (fonte $bestfile)"; CHANGES=$((CHANGES+1))
  else
    cp -a "$OUT/studiosat-radio.conf.before-backup-test" "$current"; nginx -t >/dev/null 2>&1 && systemctl reload nginx >/dev/null 2>&1 || true; info "nenhum backup melhorou HLS; mantive configuracao original"
  fi
}

section "A. IDENTIDADE / TEMPO"; date -Is; hostname -f 2>/dev/null || hostname; uptime; who || true
section "B. RECURSOS"; df -hT || true; df -ih || true; free -h || true
section "C. SESSOES E ACESSOS RECENTES"; last -Fai | head -80 || true; have lastb && lastb -Fai | head -40 || true; [[ -f /var/log/auth.log ]] && grep -E 'Accepted |sudo:|session opened|session closed' /var/log/auth.log | tail -250 || true
section "D. ALTERACOES RECENTES EM CONFIG/SCRIPTS"
for d in /etc/nginx /etc/systemd/system /usr/local/sbin /usr/local/bin; do [[ -d "$d" ]] || continue; echo "--- $d ---"; find "$d" -xdev -type f -mmin -1440 -printf '%TY-%Tm-%Td %TH:%TM:%TS %u:%g %m %p\n' 2>/dev/null | sort | tail -250 || true; done

section "E. BACKUP FORENSE PRE-REPARO"
tar -czf "$OUT/etc-nginx.tgz" /etc/nginx 2>/dev/null || true; tar -czf "$OUT/etc-systemd-system.tgz" /etc/systemd/system 2>/dev/null || true; tar -czf "$OUT/usr-local-sbin.tgz" /usr/local/sbin 2>/dev/null || true
find /etc/nginx -type f -maxdepth 3 -print0 2>/dev/null | xargs -0 sha256sum > "$OUT/nginx.sha256" 2>/dev/null || true; ls -lah --time-style=long-iso /etc/nginx/conf.d > "$OUT/nginx-conf.d-list.txt" 2>&1 || true; pass "snapshot salvo em $OUT"

section "F. NGINX"; nginx -t || true; nginx -T > "$OUT/nginx-T.txt" 2>&1 || true; systemctl status nginx --no-pager -l || true
section "G. SYSTEMD / PROCESSOS / PORTAS"; systemctl --failed --no-pager || true; systemctl list-unit-files --type=service --no-pager | grep -Ei 'studio|tps|radio|tv|ffmpeg|hls|playout|liquidsoap|icecast|nginx' || true; ps -eo pid,ppid,user,lstart,etime,%cpu,%mem,args --sort=start_time | grep -Ei '[f]fmpeg|[l]iquidsoap|[f]fplay|[m]pv|[t]ps|studio|radio|tv' | tail -250 || true; ss -lntup || true
section "H. LOGS 12H"; journalctl --since '-12 hours' --no-pager | grep -Ei 'nginx|ffmpeg|liquidsoap|studio|tps|radio|tv|playout|failed|error|killed|oom|sudo|sshd' | tail -1200 || true

section "I. MIDIA / PLAYLISTS / HLS LOCAIS"
if [[ -d /srv/tpsmedia/repository/channels ]]; then
  find /srv/tpsmedia/repository/channels -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort | tee "$OUT/channels.txt"
  while IFS= read -r ch; do [[ -n "$ch" ]] || continue; echo "--- CHANNEL $ch ---"; base="/srv/tpsmedia/repository/channels/$ch"; find "$base" -maxdepth 2 -type f \( -name '*.txt' -o -name '*.m3u8' -o -name '*.mp3' -o -name '*.m4a' -o -name '*.mp4' -o -name '*.aac' \) -printf '%TY-%Tm-%Td %TH:%TM:%TS %s %p\n' 2>/dev/null | sort | tail -35 || true; done < "$OUT/channels.txt"
else warn "/srv/tpsmedia/repository/channels nao existe"; : > "$OUT/channels.txt"; fi
find /var/www /srv -xdev -type f -name '*.m3u8' -printf '%TY-%Tm-%Td %TH:%TM:%TS %s %p\n' 2>/dev/null | sort | tail -300 | tee "$OUT/hls-files.txt" || true

section "J. ESTADO PUBLICO ANTES"; echo "PORTAL $(http_code "https://$PORTAL_HOST/") https://$PORTAL_HOST/"; radio_matrix "BEFORE"; PASS_BEFORE="$RADIO_MATRIX_COUNT"
if [[ -s "$OUT/nginx-T.txt" ]]; then grep -Eo '[A-Za-z0-9.-]*tv[A-Za-z0-9.-]*\.studiosatweb\.com\.br' "$OUT/nginx-T.txt" | sort -u > "$OUT/tv-hosts.txt" || true; else : > "$OUT/tv-hosts.txt"; fi
section "K. SITES TV ANTES"; while IFS= read -r host; do [[ -n "$host" ]] || continue; echo "TV_HTTP $(http_code "https://$host/") $host"; done < "$OUT/tv-hosts.txt"

section "L. REPARO NGINX BASICO"; recover_nginx_syntax_if_needed || true
if nginx -t >/dev/null 2>&1; then if ! systemctl is-active --quiet nginx; then systemctl restart nginx && { pass "nginx iniciado"; CHANGES=$((CHANGES+1)); } || fail "nginx nao iniciou"; else systemctl reload nginx || systemctl restart nginx || fail "nginx nao recarregou"; fi; fi

section "M. REPARO DE SERVICOS POR CANAL"
for ch in "${RADIOS[@]}"; do
  if hls_check "$ch"; then echo "SKIP $ch HLS ja esta OK"; continue; fi
  maybe_regenerate_playlist "$ch"; mapfile -t units < <(find_channel_units "$ch")
  if ((${#units[@]})); then printf 'CHANNEL_UNITS %s: %s\n' "$ch" "${units[*]}"; for unit in "${units[@]}"; do restart_unit_safe "$unit"; done; else warn "nenhum unit systemd referencia $ch"; fi
done

if [[ -s "$OUT/channels.txt" ]]; then
  while IFS= read -r ch; do [[ -n "$ch" ]] || continue; case "$ch" in radioprincipal|radiopop|radiorock|radioclassicas|radiocountry) continue;; esac; if channel_has_fresh_hls "$ch"; then echo "SKIP $ch tem HLS local fresco"; continue; fi; maybe_regenerate_playlist "$ch"; mapfile -t units < <(find_channel_units "$ch"); for unit in "${units[@]}"; do restart_unit_safe "$unit"; done; done < "$OUT/channels.txt"
fi
systemctl daemon-reload || true; sleep 4

section "N. REVALIDACAO APOS SERVICOS"; radio_matrix "AFTER_SERVICES"
if (( RADIO_MATRIX_COUNT < 5 )); then try_radio_nginx_backups_if_needed; fi
section "O. ESTADO FINAL"; nginx -t || true; radio_matrix "AFTER"; PASS_AFTER="$RADIO_MATRIX_COUNT"; echo "PORTAL_FINAL $(http_code "https://$PORTAL_HOST/") https://$PORTAL_HOST/"
section "P. TV FINAL"; while IFS= read -r host; do [[ -n "$host" ]] || continue; echo "TV_HTTP_FINAL $(http_code "https://$host/") $host"; done < "$OUT/tv-hosts.txt"
section "Q. SERVICOS FINAIS"; systemctl --failed --no-pager || true; ps -eo pid,ppid,user,lstart,etime,%cpu,%mem,args --sort=start_time | grep -Ei '[f]fmpeg|[l]iquidsoap|[f]fplay|[m]pv|[t]ps|studio|radio|tv' | tail -250 || true; find /var/www /srv -xdev -type f -name '*.m3u8' -mmin -10 -printf '%TY-%Tm-%Td %TH:%TM:%TS %s %p\n' 2>/dev/null | sort | tail -300 || true

section "RESUMO"; echo "INCIDENT_DIR=$OUT"; echo "REPORT=$REPORT"; echo "RADIOS_BEFORE=$PASS_BEFORE/5"; echo "RADIOS_AFTER=$PASS_AFTER/5"; echo "CHANGES=$CHANGES"; echo "UNRESOLVED=$UNRESOLVED"
if (( PASS_AFTER == 5 )); then echo "RADIO_RECOVERY=PASS"; else echo "RADIO_RECOVERY=PARTIAL"; fi
if (( UNRESOLVED == 0 )); then echo "NS1_EMERGENCY_RESULT=PASS_OR_RECOVERED"; else echo "NS1_EMERGENCY_RESULT=CHECK_REPORT"; fi
echo; printf 'IMPORTANTE: nao apague %s; ele contem o snapshot anterior ao reparo.\n' "$OUT"
