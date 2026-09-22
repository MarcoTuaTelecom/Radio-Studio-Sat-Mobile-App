#!/usr/bin/env bash
set -Eeuo pipefail
umask 022

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NGINX_FILE="/etc/nginx/conf.d/studiosat-radio.conf"
MARK_BEGIN="# STUDIO-SAT-NATIVE-V2 BEGIN"
MARK_END="# STUDIO-SAT-NATIVE-V2 END"
BACKUP="/root/studiosat-native-v2-nginx-$(date -u +%Y%m%dT%H%M%SZ).conf"

[[ $EUID -eq 0 ]] || { echo "Execute como root."; exit 1; }
[[ -x "$ROOT/dist/api/studiosat-api" ]] || { echo "Execute scripts/build-linux.sh primeiro."; exit 1; }
[[ -f "$ROOT/dist/web/index.html" ]] || { echo "Build web ausente."; exit 1; }
[[ -f "$NGINX_FILE" ]] || { echo "Nginx esperado não encontrado: $NGINX_FILE"; exit 1; }

install -d -o tpsmedia -g tpsmedia -m 0755 /opt/studiosat-v2/bin
install -m 0755 "$ROOT/dist/api/studiosat-api" /opt/studiosat-v2/bin/studiosat-api

install -d -o tpsmedia -g www-data -m 0755 /var/www/studiosat-v2/listen
rsync -a --delete "$ROOT/dist/web/" /var/www/studiosat-v2/listen/
chown -R tpsmedia:www-data /var/www/studiosat-v2/listen

install -d -o tpsmedia -g tpsmedia -m 0755 /etc/studiosat-v2/data
if [[ ! -f /etc/studiosat-v2/data/content.json ]]; then
  install -m 0644 "$ROOT/data/content.json" /etc/studiosat-v2/data/content.json
  chown tpsmedia:tpsmedia /etc/studiosat-v2/data/content.json
fi

install -m 0644 "$ROOT/deploy/studiosat-api-v2.service" /etc/systemd/system/studiosat-api-v2.service
systemctl daemon-reload
systemctl enable --now studiosat-api-v2.service

curl -fsS http://127.0.0.1:9080/api/v2/health | tee /tmp/studiosat-v2-health.json

cp -a "$NGINX_FILE" "$BACKUP"

python3 - "$NGINX_FILE" "$ROOT/deploy/nginx-locations-v2.conf" "$MARK_BEGIN" "$MARK_END" <<'PY'
import re,sys
from pathlib import Path

conf=Path(sys.argv[1])
snippet=Path(sys.argv[2]).read_text()
begin=sys.argv[3]
end=sys.argv[4]
text=conf.read_text()

# Remove bloco V2 anterior.
text=re.sub(rf"\n?\s*{re.escape(begin)}.*?{re.escape(end)}\s*\n?", "\n", text, flags=re.S)

# Parser simples de chaves: identifica o server{} que contém o hostname WWW.
servers=[]
i=0
while True:
    m=re.search(r"\bserver\s*\{", text[i:])
    if not m: break
    start=i+m.start()
    brace=text.find("{",start)
    depth=0
    endpos=None
    for pos in range(brace,len(text)):
        if text[pos]=="{": depth+=1
        elif text[pos]=="}":
            depth-=1
            if depth==0:
                endpos=pos
                break
    if endpos is None:
        raise SystemExit("server{} incompleto")
    servers.append((start,endpos))
    i=endpos+1

target=None
for start,endpos in servers:
    block=text[start:endpos+1]
    if "www.radio.studiosatweb.com.br" in block:
        target=(start,endpos)
        break

if not target:
    raise SystemExit("server{} de www.radio.studiosatweb.com.br não localizado")

start,endpos=target
insertion="\n    "+begin+"\n"+snippet.rstrip().replace("\n","\n    ")+"\n    "+end+"\n"
text=text[:endpos]+insertion+text[endpos:]

tmp=conf.with_name("."+conf.name+".native-v2.tmp")
tmp.write_text(text)
tmp.replace(conf)
print("NGINX_V2_PATCH=OK")
PY

if ! nginx -t; then
  cp -a "$BACKUP" "$NGINX_FILE"
  nginx -t
  systemctl reload nginx
  echo "Nginx inválido; rollback aplicado."
  exit 1
fi

systemctl reload nginx

echo
echo "V2 instalado."
echo "Portal: https://www.radio.studiosatweb.com.br/listen-v2/"
echo "API:    https://www.radio.studiosatweb.com.br/api/v2/health"
echo "Backup Nginx: $BACKUP"
