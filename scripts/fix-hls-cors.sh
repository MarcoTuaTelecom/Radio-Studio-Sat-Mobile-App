#!/usr/bin/env bash
set -Eeuo pipefail

HOST="${HOST:-radio.studiosatweb.com.br}"
ORIGIN="${ORIGIN:-https://www.radio.studiosatweb.com.br}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP_LIST="/tmp/studiosat-hls-cors-$STAMP.txt"

[[ $EUID -eq 0 ]] || { echo "FAIL execute como root" >&2; exit 1; }
for c in curl python3 grep nginx systemctl mktemp readlink; do command -v "$c" >/dev/null 2>&1 || { echo "FAIL comando ausente: $c" >&2; exit 1; }; done

check_hls(){
  local url="https://$HOST/radioprincipal/index.m3u8"
  local h b c code cors
  h="$(mktemp)"; b="$(mktemp)"; c="$(mktemp)"
  code="$(curl -ksS -L --max-redirs 6 -D "$h" -o "$b" -w '%{http_code}' \
    -H "Origin: $ORIGIN" -c "$c" -b "$c" --resolve "$HOST:443:127.0.0.1" "$url" || true)"
  cors="$(python3 - "$h" <<'PY'
import re,sys
raw=open(sys.argv[1],encoding='iso-8859-1').read().replace('\r\n','\n')
blocks=[b for b in re.split(r'\n\n+',raw) if b.lstrip().startswith('HTTP/')]
last=blocks[-1] if blocks else ''
m=re.search(r'(?im)^access-control-allow-origin:\s*(.+?)\s*$',last)
print(m.group(1).strip() if m else '')
PY
)"
  echo "HLS_HTTP_FINAL=$code"
  echo "HLS_CORS_FINAL=${cors:-MISSING}"
  if [[ "$code" == "200" ]] && grep -q '#EXTM3U' "$b" && { [[ "$cors" == "$ORIGIN" ]] || [[ "$cors" == "*" ]]; }; then
    rm -f "$h" "$b" "$c"
    return 0
  fi
  rm -f "$h" "$b" "$c"
  return 1
}

# O host atual usa um redirect de cookieCheck antes do manifesto. Se o GET final
# já retorna 200 + #EXTM3U + CORS '*' ou a origem exata, não alteramos NGINX.
if check_hls; then
  echo "HLS_CORS=PASS_ALREADY_VALID"
  exit 0
fi

mapfile -t FILES < <(
  grep -RslE "server_name[^;]*${HOST//./\.}" /etc/nginx/conf.d /etc/nginx/sites-enabled 2>/dev/null |
  while read -r f; do
    r="$(readlink -f "$f")"
    [[ "$r" == *.conf ]] && printf '%s\n' "$r"
  done | sort -u
)
((${#FILES[@]} > 0)) || { echo "FAIL vhost ativo $HOST nao encontrado" >&2; exit 1; }
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
    out=[]
    for m in re.finditer(r'(?m)^\s*server_name\s+([^;]+);',block): out += m.group(1).split()
    return out

def https(block):
    return bool(re.search(r'(?m)^\s*listen\s+[^;]*\b443\b[^;]*;',block))

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
    text=text[:s]+b+text[e:]
    open(path,'w',encoding='utf-8').write(text)
    print(f'HLS_CORS_PATCHED={path}')
    patched=True
    break
open(backup_list,'w',encoding='utf-8').write(''.join(f'{x}|{y}\n' for x,y in backups))
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

check_hls || { echo "FAIL HLS final apos ajuste"; exit 1; }
echo "HLS_CORS=PASS"
