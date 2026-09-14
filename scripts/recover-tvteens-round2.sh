#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
umask 077

CH="tvteens"
UNIT="tps-${CH}-playout.service"
BASE="/srv/tpsmedia/repository/channels/${CH}"
READY="${BASE}/ready"
PLDIR="${BASE}/playlists"
PL="${PLDIR}/playlist.txt"
HELPER="/usr/local/sbin/tps-generate-playlist-${CH}-recovery"
DROPIN_DIR="/etc/systemd/system/${UNIT}.d"
DROPIN="${DROPIN_DIR}/20-recovery-playlist.conf"
PORTAL_HOST="www.radio.studiosatweb.com.br"
PLAYER_HOST="radio.studiosatweb.com.br"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
BK="/var/backups/studiosat/RECOVERY-TVTEENS-ROUND2-${TS}"
MUTATED=0
BEFORE_ACTIVE=0
BEFORE_ENABLED=0

need(){ command -v "$1" >/dev/null 2>&1 || { echo "FATAL=MISSING_TOOL:$1" >&2; exit 70; }; }
fail(){ echo "FATAL=$*" >&2; return 1; }

[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo "FATAL=RUN_AS_ROOT" >&2; exit 77; }
for c in systemctl curl tar cp rm mkdir install ffprobe find sort sha256sum awk grep stat mktemp; do need "$c"; done
[[ -d "$READY" ]] || { echo "FATAL=READY_MISSING:$READY" >&2; exit 71; }
mkdir -p "$BK"
exec > >(tee "$BK/RECOVERY.log") 2>&1

echo "============================================================"
echo " STUDIO SAT - RECOVERY TVTEENS - ROUND 2"
echo " BACKUP_DESTA_RODADA=$BK"
echo " NAO TOCA NAS 5 RADIOS NEM NA TVKIDS"
echo "============================================================"

backup_file(){
  local src="$1" name="$2"
  if [[ -e "$src" || -L "$src" ]]; then cp -a "$src" "$BK/$name"; else : > "$BK/$name.ABSENT"; fi
}

restore_file(){
  local dst="$1" name="$2"
  rm -f -- "$dst"
  [[ -f "$BK/$name" ]] && cp -a "$BK/$name" "$dst"
}

rollback(){
  local rc=$?
  trap - ERR EXIT
  if (( MUTATED == 1 )); then
    echo "ROLLBACK=START"
    rm -rf -- "$DROPIN_DIR"
    if [[ -f "$BK/unit-dropins.tar.gz" ]]; then tar -C / -xzpf "$BK/unit-dropins.tar.gz"; fi
    restore_file "$HELPER" helper.before
    restore_file "$PL" playlist.before
    systemctl daemon-reload || true
    if (( BEFORE_ENABLED == 1 )); then systemctl enable "$UNIT" >/dev/null 2>&1 || true; else systemctl disable "$UNIT" >/dev/null 2>&1 || true; fi
    if (( BEFORE_ACTIVE == 1 )); then systemctl restart "$UNIT" || true; else systemctl stop "$UNIT" >/dev/null 2>&1 || true; fi
    echo "ROLLBACK=DONE"
  fi
  echo "BACKUP_DESTA_RODADA=$BK"
  exit "$rc"
}
trap rollback ERR EXIT

echo
echo "===== 0. GATE: PORTAL + 5 RADIOS ====="
portal_code="$(curl -ksS --max-time 12 -o "$BK/portal.before.html" -w '%{http_code}' "https://${PORTAL_HOST}/" || true)"
echo "PORTAL_BEFORE_HTTP=$portal_code"
[[ "$portal_code" == 200 ]] || fail "PORTAL_NOT_200_BEFORE"

RADIO_BEFORE=0
for r in radioprincipal radiopop radiorock radioclassicas radiocountry; do
  f="$BK/${r}.before.m3u8"
  code="$(curl -sSL --connect-timeout 3 --max-time 12 -o "$f" -w '%{http_code}' "http://127.0.0.1:8888/${r}/index.m3u8" || true)"
  if [[ "$code" == 200 ]] && grep -q '^#EXTM3U' "$f"; then RADIO_BEFORE=$((RADIO_BEFORE+1)); echo "$r BEFORE=PASS"; else echo "$r BEFORE=FAIL HTTP=$code"; fi
done
[[ "$RADIO_BEFORE" -eq 5 ]] || fail "RADIOS_BEFORE_${RADIO_BEFORE}_OF_5"

echo
echo "===== 1. BACKUP OBRIGATORIO DESTA RODADA ====="
systemctl is-active --quiet "$UNIT" && BEFORE_ACTIVE=1 || true
systemctl is-enabled --quiet "$UNIT" && BEFORE_ENABLED=1 || true
systemctl cat "$UNIT" > "$BK/unit.before.txt" 2>&1 || true
systemctl status "$UNIT" --no-pager --full > "$BK/status.before.txt" 2>&1 || true
journalctl -u "$UNIT" -n 150 --no-pager > "$BK/journal.before.txt" 2>&1 || true
if [[ -d "$DROPIN_DIR" ]]; then tar -C / -czpf "$BK/unit-dropins.tar.gz" "${DROPIN_DIR#/}"; fi
backup_file "$HELPER" helper.before
backup_file "$PL" playlist.before
backup_file /usr/local/sbin/tps-generate-playlist generic-generator.evidence
backup_file /usr/local/sbin/tps-playout-tv playout-tv.evidence
find "$READY" -maxdepth 1 -type f -printf '%TY-%Tm-%Td %TH:%TM:%TS | %s | %p\n' | sort > "$BK/ready.inventory.txt"
find "$READY" -maxdepth 1 -type f -print0 | sort -z | xargs -0 -r sha256sum > "$BK/ready.sha256"
sha256sum "$BK"/* 2>/dev/null > "$BK/SHA256SUMS.initial.txt" || true
echo "ROUND2_BACKUP=PASS"

echo
echo "===== 2. PREFLIGHT DA MIDIA TVTEENS ====="
VALID=0
TOTAL=0
while IFS= read -r -d '' f; do
  TOTAL=$((TOTAL+1))
  v="$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=nw=1:nk=1 "$f" 2>/dev/null | head -n1 || true)"
  a="$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of default=nw=1:nk=1 "$f" 2>/dev/null | head -n1 || true)"
  printf 'MEDIA=%s | video=%s | audio=%s\n' "$f" "${v:-NONE}" "${a:-NONE}"
  if [[ "$v" == h264 && ( "$a" == aac || "$a" == mp3 ) ]]; then VALID=$((VALID+1)); fi
done < <(find "$READY" -maxdepth 1 -type f \( -iname '*.mp4' -o -iname '*.mov' -o -iname '*.mkv' -o -iname '*.m4v' \) -print0 | sort -z)
echo "TVTEENS_MEDIA_TOTAL=$TOTAL"
echo "TVTEENS_MEDIA_VALID_COPY=$VALID"
[[ "$VALID" -gt 0 ]] || fail "NO_H264_AAC_OR_MP3_MEDIA_FOR_TVTEENS"

echo
echo "===== 3. INSTALANDO GERADOR ISOLADO APENAS PARA TVTEENS ====="
cat > "$BK/helper.candidate" <<'HELPER_EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
umask 022
CH="tvteens"
BASE="/srv/tpsmedia/repository/channels/${CH}"
READY="${BASE}/ready"
PLDIR="${BASE}/playlists"
PL="${PLDIR}/playlist.txt"
[[ -d "$READY" ]] || { echo "FATAL=READY_MISSING:$READY" >&2; exit 66; }
mkdir -p "$PLDIR"
tmp="$(mktemp "${PLDIR}/.playlist.recovery.XXXXXX")"
trap 'rm -f -- "$tmp"' EXIT
printf 'ffconcat version 1.0\n' > "$tmp"
count=0
while IFS= read -r -d '' f; do
  [[ -s "$f" && -r "$f" ]] || continue
  v="$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=nw=1:nk=1 "$f" 2>/dev/null | head -n1 || true)"
  a="$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of default=nw=1:nk=1 "$f" 2>/dev/null | head -n1 || true)"
  [[ "$v" == h264 && ( "$a" == aac || "$a" == mp3 ) ]] || continue
  [[ "$f" != *$'\n'* && "$f" != *$'\r'* ]] || continue
  esc=${f//\'/\'\\\'\'}
  printf "file '%s'\n" "$esc" >> "$tmp"
  count=$((count+1))
done < <(find "$READY" -maxdepth 1 -type f \( -iname '*.mp4' -o -iname '*.mov' -o -iname '*.mkv' -o -iname '*.m4v' \) -print0 | sort -z)
(( count > 0 )) || { echo "FATAL=NO_VALID_MEDIA:$CH" >&2; exit 65; }
chown tpsmedia:tpsmedia "$tmp"
chmod 0644 "$tmp"
mv -f -- "$tmp" "$PL"
trap - EXIT
printf 'PLAYLIST_OK=%s|ITEMS=%d|FILE=%s\n' "$CH" "$count" "$PL"
HELPER_EOF
bash -n "$BK/helper.candidate"
install -o root -g root -m 0755 "$BK/helper.candidate" "$HELPER"
mkdir -p "$DROPIN_DIR"
cat > "$DROPIN" <<EOF_DROPIN
[Service]
ExecStartPre=
ExecStartPre=$HELPER
EOF_DROPIN
MUTATED=1
systemctl daemon-reload
systemctl cat "$UNIT" > "$BK/unit.after-dropin.txt"
grep -Fq "ExecStartPre=$HELPER" "$BK/unit.after-dropin.txt" || fail "DROPIN_NOT_EFFECTIVE"
echo "ISOLATED_EXECSTARTPRE=PASS"

echo
echo "===== 4. GERANDO PLAYLIST E SUBINDO SOMENTE TVTEENS ====="
"$HELPER"
head -n 30 "$PL"
systemctl reset-failed "$UNIT" || true
systemctl restart "$UNIT"

LOCAL_OK=0
for i in $(seq 1 35); do
  f="$BK/tvteens.local.m3u8"
  code="$(curl -sSL --connect-timeout 2 --max-time 5 -o "$f" -w '%{http_code}' "http://127.0.0.1:8888/tvteens/index.m3u8" 2>/dev/null || true)"
  if systemctl is-active --quiet "$UNIT" && [[ "$code" == 200 ]] && grep -q '^#EXTM3U' "$f"; then LOCAL_OK=1; break; fi
  sleep 1
done
if [[ "$LOCAL_OK" -ne 1 ]]; then
  systemctl status "$UNIT" --no-pager --full || true
  journalctl -u "$UNIT" -n 100 --no-pager || true
  fail "TVTEENS_LOCAL_HLS_NOT_READY"
fi
echo "TVTEENS_LOCAL_HLS=PASS"

echo
echo "===== 5. TESTE PUBLICO TVTEENS ====="
PUBLIC_OK=0
for host in tvteens.studiosatweb.com.br www.tvteens.studiosatweb.com.br; do
  f="$BK/${host}.m3u8"
  code="$(curl -kLsS --max-redirs 6 --max-time 12 -o "$f" -w '%{http_code}' "https://${host}/tvteens/index.m3u8" 2>/dev/null || true)"
  if [[ "$code" == 200 ]] && grep -q '^#EXTM3U' "$f"; then echo "$host HLS=PASS"; PUBLIC_OK=$((PUBLIC_OK+1)); else echo "$host HLS=FAIL HTTP=$code"; fi
done

echo
echo "===== 6. REGRESSION GATE: PORTAL + 5 RADIOS ====="
portal_after="$(curl -ksS --max-time 12 -o "$BK/portal.after.html" -w '%{http_code}' "https://${PORTAL_HOST}/" || true)"
[[ "$portal_after" == 200 ]] || fail "PORTAL_REGRESSION_HTTP_$portal_after"
RADIO_AFTER=0
for r in radioprincipal radiopop radiorock radioclassicas radiocountry; do
  lf="$BK/${r}.after-local.m3u8"
  lc="$(curl -sSL --connect-timeout 3 --max-time 12 -o "$lf" -w '%{http_code}' "http://127.0.0.1:8888/${r}/index.m3u8" || true)"
  pf="$BK/${r}.after-public.m3u8"
  pc="$(curl -ksSL --resolve "$PLAYER_HOST:443:127.0.0.1" --connect-timeout 3 --max-time 12 -o "$pf" -w '%{http_code}' "https://${PLAYER_HOST}/${r}/index.m3u8" || true)"
  if [[ "$lc" == 200 && "$pc" == 200 ]] && grep -q '^#EXTM3U' "$lf" && grep -q '^#EXTM3U' "$pf"; then RADIO_AFTER=$((RADIO_AFTER+1)); echo "$r AFTER=PASS"; else echo "$r AFTER=FAIL local=$lc public=$pc"; fi
done
[[ "$RADIO_AFTER" -eq 5 ]] || fail "RADIO_REGRESSION_${RADIO_AFTER}_OF_5"

echo
echo "===== 7. FINAL ====="
systemctl is-active "$UNIT"
echo "PORTAL=PASS"
echo "RADIOS=5/5"
echo "TVTEENS_LOCAL=PASS"
echo "TVTEENS_PUBLIC_HOSTS=$PUBLIC_OK/2"
echo "BACKUP_DESTA_RODADA=$BK"
if (( PUBLIC_OK > 0 )); then echo "ROUND2_TVTEENS=PASS"; else echo "ROUND2_TVTEENS=PLAYOUT_PASS_PUBLIC_ROUTING_PENDING"; fi
trap - ERR EXIT
