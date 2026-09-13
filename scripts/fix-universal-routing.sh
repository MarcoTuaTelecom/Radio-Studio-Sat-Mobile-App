#!/usr/bin/env bash
set -Eeuo pipefail

PORTAL_ROOT="${PORTAL_ROOT:-/var/www/studiosat-radio-portal}"
HOST="${HOST:-www.radio.studiosatweb.com.br}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP_LIST="/tmp/studiosat-universal-nginx-$STAMP.txt"

[[ $EUID -eq 0 ]] || { echo "FAIL execute como root" >&2; exit 1; }
[[ -f "$PORTAL_ROOT/app/index.html" ]] || { echo "FAIL app/index.html ausente" >&2; exit 1; }
[[ -f "$PORTAL_ROOT/listen/index.html" ]] || { echo "FAIL listen/index.html ausente" >&2; exit 1; }

mapfile -t FILES < <(
  grep -RslE "server_name[^;]*${HOST//./\.}" /etc/nginx/conf.d /etc/nginx/sites-enabled 2>/dev/null |
  while read -r f; do readlink -f "$f"; done | sort -u
)

((${#FILES[@]} > 0)) || { echo "FAIL vhost $HOST nao encontrado" >&2; exit 1; }
printf 'VHOST_CANDIDATE=%s\n' "${FILES[@]}"

python3 - "$HOST" "$PORTAL_ROOT" "$STAMP" "$BACKUP_LIST" "${FILES[@]}" <<'PY'
import sys,re,shutil
host,root,stamp,backup_list,*files=sys.argv[1:]
marker_a='# STUDIO_SAT_UNIVERSAL_ROUTES_BEGIN'
marker_b='# STUDIO_SAT_UNIVERSAL_ROUTES_END'
snippet=f'''

    {marker_a}
    location = /app {{
        return 301 /app/;
    }}

    location = /app/ {{
        root {root};
        try_files /app/index.html =404;
        add_header Cache-Control "no-store, no-cache, must-revalidate, max-age=0" always;
        add_header X-StudioSat-Route "universal-installer" always;
    }}

    location = /listen {{
        return 301 /listen/;
    }}

    location = /listen/ {{
        root {root};
        try_files /listen/index.html =404;
        add_header Cache-Control "no-store, no-cache, must-revalidate, max-age=0" always;
        add_header X-StudioSat-Route "web-app" always;
    }}

    location = /listen/manifest.webmanifest {{
        root {root};
        try_files /listen/manifest.webmanifest =404;
        default_type application/manifest+json;
        add_header Cache-Control "no-cache" always;
    }}

    location = /listen/sw.js {{
        root {root};
        try_files /listen/sw.js =404;
        default_type application/javascript;
        add_header Cache-Control "no-cache" always;
        add_header Service-Worker-Allowed "/listen/" always;
    }}

    location ^~ /listen/ {{
        root {root};
        try_files $uri =404;
    }}
    {marker_b}
'''

def blocks(text):
    out=[]
    for m in re.finditer(r'(?m)^\s*server\s*\{',text):
        op=text.find('{',m.start(),m.end()); depth=0
        for i in range(op,len(text)):
            if text[i]=='{': depth+=1
            elif text[i]=='}':
                depth-=1
                if depth==0:
                    out.append((m.start(),i+1,text[m.start():i+1])); break
    return out

def names(block):
    n=[]
    for m in re.finditer(r'(?m)^\s*server_name\s+([^;]+);',block): n += m.group(1).split()
    return n

def https(block):
    return bool(re.search(r'(?m)^\s*listen\s+[^;]*\b443\b[^;]*;',block))

patched=False; backups=[]
for path in files:
    text=open(path,encoding='utf-8').read()
    target=None
    for s,e,b in blocks(text):
        if host in names(b) and https(b): target=(s,e,b); break
    if not target: continue
    s,e,b=target
    # replace our previous managed section if present
    b=re.sub(r'\n\s*# STUDIO_SAT_UNIVERSAL_ROUTES_BEGIN.*?# STUDIO_SAT_UNIVERSAL_ROUTES_END\s*', '\n', b, flags=re.S)
    pos=b.rfind('}')
    b=b[:pos]+snippet+b[pos:]
    backup=f'{path}.bak-{stamp}'
    shutil.copy2(path,backup); backups.append((path,backup))
    text=text[:s]+b+text[e:]
    open(path,'w',encoding='utf-8').write(text)
    print(f'PATCHED={path}')
    patched=True
    break

open(backup_list,'w').write(''.join(f'{a}|{b}\n' for a,b in backups))
if not patched:
    raise SystemExit('FAIL: HTTPS vhost correto nao encontrado')
PY

if ! nginx -t; then
  echo "ROLLBACK nginx"
  while IFS='|' read -r a b; do [[ -f "$b" ]] && cp -a "$b" "$a"; done < "$BACKUP_LIST"
  nginx -t || true
  exit 1
fi
systemctl reload nginx
sleep 1

echo "===== TESTE /app/ ====="
curl -ksSI --resolve "$HOST:443:127.0.0.1" "https://$HOST/app/"
APP="$(curl -ksS --resolve "$HOST:443:127.0.0.1" "https://$HOST/app/")"
grep -q 'CENTRAL OFICIAL DE INSTALAÇÃO' <<<"$APP" || { echo "FAIL /app/ ainda nao entrega central"; exit 1; }

echo "===== TESTE /listen/ ====="
curl -ksSI --resolve "$HOST:443:127.0.0.1" "https://$HOST/listen/"
LISTEN="$(curl -ksS --resolve "$HOST:443:127.0.0.1" "https://$HOST/listen/")"
grep -q 'Studio Sat Principal' <<<"$LISTEN" || { echo "FAIL /listen/ ainda nao entrega web app"; exit 1; }

echo "UNIVERSAL_NGINX=PASS"
