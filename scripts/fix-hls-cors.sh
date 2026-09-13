#!/usr/bin/env bash
set -Eeuo pipefail

HOST="${HOST:-radio.studiosatweb.com.br}"
ORIGIN="${ORIGIN:-https://www.radio.studiosatweb.com.br}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP_LIST="/tmp/studiosat-hls-cors-$STAMP.txt"

[[ $EUID -eq 0 ]] || { echo "FAIL execute como root" >&2; exit 1; }

mapfile -t FILES < <(
  grep -RslE "server_name[^;]*${HOST//./\.}" /etc/nginx/conf.d /etc/nginx/sites-enabled 2>/dev/null |
  while read -r f; do readlink -f "$f"; done | sort -u
)
((${#FILES[@]} > 0)) || { echo "FAIL vhost $HOST nao encontrado" >&2; exit 1; }
printf 'HLS_VHOST_CANDIDATE=%s\n' "${FILES[@]}"

python3 - "$HOST" "$ORIGIN" "$STAMP" "$BACKUP_LIST" "${FILES[@]}" <<'PY'
import sys,re,shutil
host,origin,stamp,backup_list,*files=sys.argv[1:]
a='# STUDIO_SAT_HLS_CORS_BEGIN'; z='# STUDIO_SAT_HLS_CORS_END'
snippet=f'''

    {a}
    add_header Access-Control-Allow-Origin "{origin}" always;
    add_header Access-Control-Allow-Methods "GET, HEAD, OPTIONS" always;
    add_header Access-Control-Allow-Headers "Origin, Range, Accept, Content-Type" always;
    add_header Access-Control-Expose-Headers "Content-Length, Content-Range, Accept-Ranges" always;
    {z}
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
    for m in re.finditer(r'(?m)^\s*server_name\s+([^;]+);',block): n+=m.group(1).split()
    return n

def https(block): return bool(re.search(r'(?m)^\s*listen\s+[^;]*\b443\b[^;]*;',block))

patched=False; backups=[]
for path in files:
    text=open(path,encoding='utf-8').read(); target=None
    for s,e,b in blocks(text):
        if host in names(b) and https(b): target=(s,e,b); break
    if not target: continue
    s,e,b=target
    b=re.sub(r'\n\s*# STUDIO_SAT_HLS_CORS_BEGIN.*?# STUDIO_SAT_HLS_CORS_END\s*','\n',b,flags=re.S)
    pos=b.rfind('}')
    b=b[:pos]+snippet+b[pos:]
    backup=f'{path}.bak-{stamp}'; shutil.copy2(path,backup); backups.append((path,backup))
    text=text[:s]+b+text[e:]; open(path,'w',encoding='utf-8').write(text)
    print(f'HLS_CORS_PATCHED={path}'); patched=True; break
open(backup_list,'w').write(''.join(f'{x}|{y}\n' for x,y in backups))
if not patched: raise SystemExit('FAIL: HTTPS HLS vhost correto nao encontrado')
PY

if ! nginx -t; then
  echo "ROLLBACK HLS CORS"
  while IFS='|' read -r a b; do [[ -f "$b" ]] && cp -a "$b" "$a"; done < "$BACKUP_LIST"
  nginx -t || true
  exit 1
fi
systemctl reload nginx
sleep 1

URL="https://$HOST/radioprincipal/index.m3u8"
HEADERS="$(curl -ksSI -H "Origin: $ORIGIN" --resolve "$HOST:443:127.0.0.1" "$URL")"
printf '%s\n' "$HEADERS"
grep -qi '^HTTP/2 200\|^HTTP/1\.1 200' <<<"$HEADERS" || { echo "FAIL HLS HTTP"; exit 1; }
grep -qi "^access-control-allow-origin: $ORIGIN" <<<"$HEADERS" || { echo "FAIL HLS CORS ausente"; exit 1; }
echo "HLS_CORS=PASS"
