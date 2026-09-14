#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
umask 077

TS="$(date -u +%Y%m%dT%H%M%SZ)"
BASE="/var/backups/studiosat/MENOS1-PRE-${TS}"
XR="${BASE}/RAIOX"
DL="/home/marco/backup"
PRE_ARCHIVE="${DL}/STUDIOSAT-MENOS1-PRE-${TS}.tar.gz"
XR_ARCHIVE="${DL}/STUDIOSAT-RAIOX-PRE-MELHORIAS-${TS}.tar.gz"
SUMMARY_DL="${DL}/STUDIOSAT-RAIOX-PRE-MELHORIAS-${TS}.txt"
CHANNELS=(radioprincipal radiopop radiorock radioclassicas radiocountry tvkids tvteens tvviva tvmaisjovem)
RADIOS=(radioprincipal radiopop radiorock radioclassicas radiocountry)
TVS=(tvkids tvteens tvviva tvmaisjovem)

mkdir -p "$BASE" "$XR" "$DL"
exec > >(tee "$BASE/MASTER.log") 2>&1

section(){ printf '\n================================================================\n%s\n================================================================\n' "$*"; }
run_capture(){ local file="$1"; shift; { "$@"; } >"$file" 2>&1 || true; }

section "STUDIO SAT - MENOS1 PRE + RAIO X COMPLETO"
echo "UTC=$TS"
echo "HOST=$(hostname -f 2>/dev/null || hostname)"
echo "BASE=$BASE"
echo "PRE_ARCHIVE=$PRE_ARCHIVE"
echo "XR_ARCHIVE=$XR_ARCHIVE"
echo "MODO=BACKUP_E_LEITURA_SOMENTE"
echo "SERVICOS_NAO_SERAO_REINICIADOS=YES"

section "1. INVENTARIO DO BACKUP MENOS1 PRE"
ABS=()
add_path(){ [[ -e "$1" || -L "$1" ]] && ABS+=("$1") || true; }
add_path /etc/nginx
add_path /etc/tpsmedia
add_path /etc/systemd/system
add_path /etc/bind
add_path /etc/letsencrypt
add_path /usr/local/sbin
add_path /var/www
add_path /srv/tpsweb
add_path /opt/studiosat-portal-cms
add_path /var/lib/studiosat-portal-cms
for ch in "${CHANNELS[@]}"; do add_path "/srv/tpsmedia/repository/channels/${ch}/playlists"; done

printf '%s\n' "${ABS[@]}" | tee "$BASE/backup-paths.txt"
REQ_KB="$(du -sk "${ABS[@]}" 2>/dev/null | awk '{s+=$1} END{print s+0}')"
FREE_KB="$(df -Pk "$DL" | awk 'NR==2{print $4}')"
echo "ESTIMATED_SOURCE_KB=$REQ_KB"
echo "FREE_KB=$FREE_KB"
if (( FREE_KB < REQ_KB + 524288 )); then
  echo "FATAL=ESPACO_INSUFICIENTE_PARA_BACKUP"
  exit 73
fi

section "2. CRIANDO BACKUP MENOS1 PRE"
REL=()
for p in "${ABS[@]}"; do REL+=("${p#/}"); done

tar -C / \
  --numeric-owner --acls --xattrs \
  --exclude='var/www/**/.cache' \
  --exclude='var/www/**/node_modules' \
  -czpf "$PRE_ARCHIVE" \
  "${REL[@]}"
sha256sum "$PRE_ARCHIVE" | tee "$PRE_ARCHIVE.sha256"
echo "MENOS1_PRE_BACKUP=PASS"

section "3. SISTEMA / RECURSOS"
{
  echo "### DATE"; date -Is
  echo "### HOST"; hostnamectl 2>/dev/null || true
  echo "### UNAME"; uname -a
  echo "### UPTIME"; uptime
  echo "### MEMORY"; free -h
  echo "### DISK"; df -hT
  echo "### INODES"; df -ih
  echo "### TOP"; ps aux --sort=-%cpu | head -40
} > "$XR/system.txt" 2>&1

section "4. VERSOES"
{
  nginx -v 2>&1 || true
  ffmpeg -version 2>&1 | head -3 || true
  ffprobe -version 2>&1 | head -2 || true
  node -v 2>/dev/null || true
  npm -v 2>/dev/null || true
  python3 --version 2>/dev/null || true
  /usr/local/bin/mediamtx --version 2>/dev/null || mediamtx --version 2>/dev/null || true
} > "$XR/versions.txt"

section "5. NGINX COMPLETO"
nginx -t > "$XR/nginx-test.txt" 2>&1 || true
nginx -T > "$XR/nginx-T.txt" 2>&1 || true
find /etc/nginx -xdev -printf '%y | %m | %u:%g | %s | %TY-%Tm-%Td %TH:%TM:%TS | %p\n' 2>/dev/null | sort > "$XR/nginx-tree.txt"
find /etc/nginx -xdev -type f -print0 2>/dev/null | sort -z | xargs -0 -r sha256sum > "$XR/nginx-sha256.txt"
grep -RInE 'server_name|listen |root |alias |proxy_pass|ssl_certificate|return 30[12]|location ' /etc/nginx/conf.d 2>/dev/null > "$XR/nginx-vhosts-map.txt" || true

section "6. TLS / CERTIFICADOS"
{
  find /etc/letsencrypt/live -maxdepth 2 -type l -printf '%p -> %l\n' 2>/dev/null | sort
  for f in /etc/letsencrypt/live/*/fullchain.pem; do
    [[ -r "$f" ]] || continue
    echo "### $f"
    openssl x509 -in "$f" -noout -subject -issuer -dates -ext subjectAltName 2>/dev/null || true
  done
} > "$XR/tls.txt"

section "7. SYSTEMD / SERVICOS"
systemctl --failed --no-pager > "$XR/systemd-failed.txt" 2>&1 || true
systemctl list-unit-files --no-pager > "$XR/systemd-unit-files.txt" 2>&1 || true
systemctl list-timers --all --no-pager > "$XR/systemd-timers.txt" 2>&1 || true

UNITS=(nginx.service tps-mediamtx.service studiosat-portal-cms.service bind9.service named.service)
for ch in "${CHANNELS[@]}"; do UNITS+=("tps-${ch}-playout.service"); done
: > "$XR/services-summary.txt"
for u in "${UNITS[@]}"; do
  echo "### $u" >> "$XR/services-summary.txt"
  systemctl is-enabled "$u" >> "$XR/services-summary.txt" 2>&1 || true
  systemctl is-active "$u" >> "$XR/services-summary.txt" 2>&1 || true
  systemctl show "$u" -p LoadState -p ActiveState -p SubState -p MainPID -p FragmentPath -p DropInPaths -p ExecMainStatus --no-pager >> "$XR/services-summary.txt" 2>&1 || true
  systemctl cat "$u" > "$XR/${u}.cat.txt" 2>&1 || true
  journalctl -u "$u" --since '-24 hours' -n 300 --no-pager > "$XR/${u}.journal.txt" 2>&1 || true
done

section "8. PROCESSOS / PORTAS"
ss -lntup > "$XR/ss-lntup.txt" 2>&1 || true
ps -eo pid,ppid,user,etimes,%cpu,%mem,args --sort=pid > "$XR/processes.txt"
grep -Ei 'ffmpeg|mediamtx|nginx|studiosat|python.*8789' "$XR/processes.txt" > "$XR/processes-studiosat.txt" || true

section "9. MEDIAMTX"
if [[ -f /etc/tpsmedia/mediamtx/mediamtx.yml ]]; then
  cp -a /etc/tpsmedia/mediamtx/mediamtx.yml "$XR/mediamtx.yml"
  sha256sum /etc/tpsmedia/mediamtx/mediamtx.yml > "$XR/mediamtx.sha256"
fi
find /etc/tpsmedia -xdev -printf '%y | %m | %u:%g | %s | %TY-%Tm-%Td %TH:%TM:%TS | %p\n' 2>/dev/null | sort > "$XR/tpsmedia-tree.txt"

section "10. PORTAL / PLAYER / LISTEN"
: > "$XR/web-roots.txt"
for d in /var/www/studiosat-radio /var/www/studiosat-radio-portal /var/www/studiosat-radio-player /var/www/portais /srv/tpsweb/www; do
  [[ -e "$d" ]] || continue
  echo "### $d" >> "$XR/web-roots.txt"
  du -sh "$d" >> "$XR/web-roots.txt" 2>&1 || true
  find "$d" -maxdepth 5 -type f -printf '%m | %u:%g | %s | %TY-%Tm-%Td %TH:%TM:%TS | %p\n' 2>/dev/null | sort >> "$XR/web-roots.txt"
done
find /var/www -type f \( -name '*.html' -o -name '*.js' -o -name '*.css' -o -name '*.json' -o -name '*.webmanifest' \) -print0 2>/dev/null | sort -z | xargs -0 -r sha256sum > "$XR/web-sha256.txt"

section "11. PORTAL HTTP"
: > "$XR/http-portal.txt"
URLS=(
  'https://www.radio.studiosatweb.com.br/'
  'https://radio.studiosatweb.com.br/'
  'https://radio.studiosatweb.com.br/listen/'
  'https://www.radio.studiosatweb.com.br/listen/'
  'https://www.radio.studiosatweb.com.br/api/public/content'
  'https://radio.studiosatweb.com.br/app/'
  'https://radio.studiosatweb.com.br/app-web/'
)
for url in "${URLS[@]}"; do
  tmp="$(mktemp)"
  code="$(curl -kLsS --max-redirs 8 --connect-timeout 4 --max-time 15 -o "$tmp" -w '%{http_code}' "$url" 2>/dev/null || true)"
  size="$(wc -c < "$tmp" 2>/dev/null || echo 0)"
  ctype="$(curl -kLsSI --max-redirs 8 --connect-timeout 4 --max-time 15 "$url" 2>/dev/null | awk -F': ' 'tolower($1)=="content-type"{v=$2} END{gsub("\\r","",v); print v}')"
  printf '%-65s HTTP=%-4s SIZE=%-8s TYPE=%s\n' "$url" "$code" "$size" "$ctype" >> "$XR/http-portal.txt"
  rm -f "$tmp"
done

section "12. NOVE EMISSORAS - ESTADO E HLS"
LOCAL_OK=0
PUBLIC_OK=0
: > "$XR/channels-health.txt"
for ch in "${CHANNELS[@]}"; do
  unit="tps-${ch}-playout.service"
  state="$(systemctl is-active "$unit" 2>/dev/null || true)"
  lf="$XR/${ch}.local.m3u8"
  lc="$(curl -sSL --connect-timeout 3 --max-time 12 -o "$lf" -w '%{http_code}' "http://127.0.0.1:8888/${ch}/index.m3u8" 2>/dev/null || true)"
  if [[ "$lc" == 200 ]] && grep -q '^#EXTM3U' "$lf"; then lres=PASS; LOCAL_OK=$((LOCAL_OK+1)); else lres=FAIL; fi
  if [[ "$ch" == radio* ]]; then
    purl="https://radio.studiosatweb.com.br/${ch}/index.m3u8"
  else
    purl="https://${ch}.studiosatweb.com.br/${ch}/index.m3u8"
  fi
  pf="$XR/${ch}.public.m3u8"
  pc="$(curl -kLsS --max-redirs 8 --connect-timeout 3 --max-time 15 -o "$pf" -w '%{http_code}' "$purl" 2>/dev/null || true)"
  if [[ "$pc" == 200 ]] && grep -q '^#EXTM3U' "$pf"; then pres=PASS; PUBLIC_OK=$((PUBLIC_OK+1)); else pres=FAIL; fi
  printf '%-18s service=%-10s local=%-4s/%-4s public=%-4s/%-4s url=%s\n' "$ch" "$state" "$lc" "$lres" "$pc" "$pres" "$purl" >> "$XR/channels-health.txt"
done

section "13. REPOSITORIO DE MIDIA / PLAYLISTS"
: > "$XR/media-inventory.txt"
: > "$XR/playlists.txt"
for ch in "${CHANNELS[@]}"; do
  base="/srv/tpsmedia/repository/channels/$ch"
  echo "### $ch" >> "$XR/media-inventory.txt"
  for sub in ready canonical playlists rejected logs; do
    d="$base/$sub"
    if [[ -d "$d" ]]; then
      cnt="$(find "$d" -maxdepth 1 -type f | wc -l)"
      sz="$(du -sh "$d" 2>/dev/null | awk '{print $1}')"
      echo "$sub files=$cnt size=$sz" >> "$XR/media-inventory.txt"
      find "$d" -maxdepth 1 -type f -printf '%s | %TY-%Tm-%Td %TH:%TM:%TS | %p\n' 2>/dev/null | sort >> "$XR/media-inventory.txt"
    else
      echo "$sub MISSING" >> "$XR/media-inventory.txt"
    fi
  done
  pl="$base/playlists/playlist.txt"
  echo "### $ch" >> "$XR/playlists.txt"
  if [[ -f "$pl" ]]; then
    sha256sum "$pl" >> "$XR/playlists.txt"
    sed -n '1,80p' "$pl" >> "$XR/playlists.txt"
    while IFS= read -r ref; do
      [[ -e "$ref" ]] || echo "BROKEN_REF=$ref" >> "$XR/playlists.txt"
    done < <(sed -n "s/^file '\(.*\)'$/\1/p" "$pl")
  else
    echo "PLAYLIST_MISSING" >> "$XR/playlists.txt"
  fi
  sample="$(find "$base/ready" "$base/canonical" -maxdepth 1 -type f \( -iname '*.mp4' -o -iname '*.mp3' -o -iname '*.m4a' -o -iname '*.aac' -o -iname '*.mkv' \) -print 2>/dev/null | head -n1 || true)"
  if [[ -n "$sample" ]]; then
    echo "SAMPLE=$sample" >> "$XR/media-inventory.txt"
    ffprobe -v error -show_entries stream=index,codec_type,codec_name,width,height,r_frame_rate,sample_rate,channels -of compact=p=0:nk=0 "$sample" >> "$XR/media-inventory.txt" 2>&1 || true
  fi
done

section "14. HELPERS / SCRIPTS CRITICOS"
find /usr/local/sbin -maxdepth 1 -type f \( -name 'tps-*' -o -name '*studiosat*' \) -print0 2>/dev/null | sort -z | xargs -0 -r sha256sum > "$XR/helpers-sha256.txt"
for f in /usr/local/sbin/tps-generate-playlist /usr/local/sbin/tps-playout-radio /usr/local/sbin/tps-playout-tv; do
  [[ -f "$f" ]] || continue
  { echo "### $f"; nl -ba "$f"; } >> "$XR/helpers-content.txt"
done

section "15. BIND / DNS"
{
  named-checkconf 2>&1 || true
  if [[ -f /etc/bind/zones/db.studiosatweb.com.br ]]; then named-checkzone studiosatweb.com.br /etc/bind/zones/db.studiosatweb.com.br 2>&1 || true; fi
  grep -RInE 'studiosatweb|zone |file ' /etc/bind 2>/dev/null || true
} > "$XR/bind.txt"
for h in studiosatweb.com.br www.studiosatweb.com.br radio.studiosatweb.com.br www.radio.studiosatweb.com.br radioprincipal.studiosatweb.com.br radiopop.studiosatweb.com.br radiorock.studiosatweb.com.br radioclassicas.studiosatweb.com.br radiocountry.studiosatweb.com.br tvkids.studiosatweb.com.br tvteens.studiosatweb.com.br tvviva.studiosatweb.com.br tvmaisjovem.studiosatweb.com.br; do
  { echo "### $h"; getent ahosts "$h" 2>/dev/null | head -10 || true; command -v dig >/dev/null 2>&1 && dig +short "$h" A || true; } >> "$XR/dns-public.txt"
done

section "16. FIREWALL / REDE"
{
  ip addr
  ip route
  command -v ufw >/dev/null 2>&1 && ufw status verbose || true
  command -v nft >/dev/null 2>&1 && nft list ruleset || true
} > "$XR/network-firewall.txt" 2>&1

section "17. GIT / ALTERACOES DE PROJETO"
: > "$XR/git.txt"
for repo in /root/Radio-Studio-Sat-Mobile-App /root/Projeto-StudioSat-Web-Radios-e-TVs-; do
  [[ -d "$repo/.git" ]] || continue
  {
    echo "### $repo"
    git -C "$repo" status --short --branch
    git -C "$repo" log -20 --date=iso --pretty=format:'%h | %ad | %an | %s'
    echo
    git -C "$repo" stash list
    echo
  } >> "$XR/git.txt" 2>&1 || true
done

section "18. LOGS RECENTES DE ERRO"
{
  journalctl --since '-12 hours' -p warning..alert --no-pager -n 1000 || true
} > "$XR/journal-warning-12h.txt" 2>&1

section "19. RESUMO AUTOMATICO"
PORTAL_CODE="$(awk '$1=="https://www.radio.studiosatweb.com.br/"{for(i=1;i<=NF;i++) if($i ~ /^HTTP=/){split($i,a,"="); print a[2]}}' "$XR/http-portal.txt" | tail -1)"
PLAYER_CODE="$(awk '$1=="https://radio.studiosatweb.com.br/listen/"{for(i=1;i<=NF;i++) if($i ~ /^HTTP=/){split($i,a,"="); print a[2]}}' "$XR/http-portal.txt" | tail -1)"
FAILED_COUNT="$(systemctl --failed --no-legend 2>/dev/null | grep -c . || true)"
NGINX_OK=NO; nginx -t >/dev/null 2>&1 && NGINX_OK=YES
MEDIAMTX_STATE="$(systemctl is-active tps-mediamtx.service 2>/dev/null || true)"
{
  echo "STUDIOSAT_RAIOX_PRE_MELHORIAS"
  echo "UTC=$TS"
  echo "MENOS1_PRE_BACKUP=PASS"
  echo "BACKUP=$PRE_ARCHIVE"
  echo "NGINX_OK=$NGINX_OK"
  echo "MEDIAMTX=$MEDIAMTX_STATE"
  echo "PORTAL_HTTP=${PORTAL_CODE:-UNKNOWN}"
  echo "LISTEN_HTTP=${PLAYER_CODE:-UNKNOWN}"
  echo "HLS_LOCAL=$LOCAL_OK/9"
  echo "HLS_PUBLIC=$PUBLIC_OK/9"
  echo "SYSTEMD_FAILED=$FAILED_COUNT"
  echo "PRODUCTION_SERVICES_RESTARTED=NO"
  echo "PRODUCTION_CONFIG_CHANGED=NO"
} | tee "$BASE/SUMMARY.txt"
cp -a "$BASE/SUMMARY.txt" "$SUMMARY_DL"

section "20. EMPACOTANDO RAIO X"
tar -C "$BASE" -czpf "$XR_ARCHIVE" RAIOX SUMMARY.txt MASTER.log backup-paths.txt
sha256sum "$XR_ARCHIVE" | tee "$XR_ARCHIVE.sha256"

if id marco >/dev/null 2>&1; then
  chown marco:marco "$PRE_ARCHIVE" "$PRE_ARCHIVE.sha256" "$XR_ARCHIVE" "$XR_ARCHIVE.sha256" "$SUMMARY_DL"
fi
chmod 600 "$PRE_ARCHIVE" "$PRE_ARCHIVE.sha256" "$XR_ARCHIVE" "$XR_ARCHIVE.sha256"
chmod 640 "$SUMMARY_DL"

section "FINAL"
cat "$BASE/SUMMARY.txt"
echo "RAIOX=PASS"
echo "RAIOX_DIR=$XR"
echo "RAIOX_REPORT=$SUMMARY_DL"
echo "RAIOX_PACKAGE=$XR_ARCHIVE"
echo "RAIOX_SHA256=$XR_ARCHIVE.sha256"
echo "BACKUP_MENOS1=$PRE_ARCHIVE"
echo "BACKUP_SHA256=$PRE_ARCHIVE.sha256"
echo "NEXT=ANALISAR_RAIOX_ANTES_DE_QUALQUER_MELHORIA"
