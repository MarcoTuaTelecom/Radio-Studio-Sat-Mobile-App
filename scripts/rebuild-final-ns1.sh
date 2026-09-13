#!/usr/bin/env bash
set -Eeuo pipefail

REPO="${REPO:-/root/Radio-Studio-Sat-Mobile-App}"
KEY="${KEY:-/root/.ssh/id_ed25519_studiosat_mobile}"
VERSION="${VERSION:-1.2.0}"
PORTAL_ROOT="${PORTAL_ROOT:-/var/www/studiosat-radio-portal}"
PUBLIC_HOST="${PUBLIC_HOST:-https://www.radio.studiosatweb.com.br}"
STREAM_HOST="${STREAM_HOST:-https://radio.studiosatweb.com.br}"
LOCK="/var/lock/studiosat-final-rebuild.lock"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP="/root/studiosat-final-rebuild/$TS"
BUILD_IOS="${BUILD_IOS:-0}"

exec 9>"$LOCK"
flock -n 9 || { echo "ERRO: outro rebuild Studio Sat esta em execucao"; exit 1; }

ok(){ printf '\nPASS  %s\n' "$*"; }
fail(){ printf '\nFAIL  %s\n' "$*" >&2; exit 1; }
section(){ printf '\n===== %s =====\n' "$*"; }

[[ $EUID -eq 0 ]] || fail "execute como root"
for c in git ssh node npm npx python3 curl nginx sha256sum file unzip flock; do command -v "$c" >/dev/null 2>&1 || fail "comando ausente: $c"; done
[[ -f "$KEY" ]] || fail "chave GitHub ausente: $KEY"
[[ -d "$REPO/.git" ]] || fail "repositorio ausente: $REPO"
mkdir -p "$BACKUP"
cd "$REPO"

export GIT_SSH_COMMAND="ssh -i $KEY -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=accept-new"
git config core.fileMode false
git config core.sshCommand "$GIT_SSH_COMMAND"

section "1. SINCRONIZACAO SEGURA"
if [[ -n "$(git status --porcelain)" ]]; then
  git status --short | tee "$BACKUP/git-status-before.txt"
  git diff > "$BACKUP/worktree-before.patch" || true
  git diff --cached > "$BACKUP/index-before.patch" || true
  git stash push -u -m "studiosat-final-rebuild-$TS"
  echo "STASH_CREATED=1"
fi
SSH_OUT="$(ssh -i "$KEY" -o IdentitiesOnly=yes -o BatchMode=yes -T git@github.com 2>&1 || true)"
printf '%s\n' "$SSH_OUT"
grep -qi 'successfully authenticated' <<<"$SSH_OUT" || fail "GitHub SSH nao autenticou"
git fetch origin main
git checkout main
git pull --ff-only origin main
ok "repositorio sincronizado: $(git rev-parse --short HEAD)"

section "2. BACKUP DOS ARQUIVOS QUE SERAO ALTERADOS"
for f in App.tsx src/components/MediaCarousel.tsx web/download/index.html app.json package.json; do
  [[ -f "$f" ]] && cp -a "$f" "$BACKUP/$(echo "$f" | tr '/' '_')"
done
ok "backup em $BACKUP"

section "3. EXTRAINDO AS ARTES EXATAS DA REFERENCIA"
cat > scripts/extract-reference-assets.py <<'PY'
from pathlib import Path
import base64, re

root=Path(__file__).resolve().parents[1]
html=(root/'web/pwa/index.html').read_text(encoding='utf-8')
out=root/'web/pwa/reference'
out.mkdir(parents=True, exist_ok=True)
imgs=re.findall(r'data:image/jpeg;base64,([A-Za-z0-9+/=]+)', html)
if len(imgs) < 8:
    raise SystemExit(f'ERRO: esperava pelo menos 8 imagens JPEG embutidas no PWA; encontrei {len(imgs)}')
names=[
 'hero-reference.jpg',
 'artist-reference.jpg',
 'promo-reference.jpg',
 'station-principal.jpg',
 'station-pop.jpg',
 'station-rock.jpg',
 'station-classicas.jpg',
 'station-country.jpg',
]
for name,data in zip(names,imgs[:8]):
    raw=base64.b64decode(data)
    if not raw.startswith(b'\xff\xd8\xff'):
        raise SystemExit(f'ERRO: {name} nao e JPEG valido')
    (out/name).write_bytes(raw)
    print(f'ASSET={name} BYTES={len(raw)}')
print('REFERENCE_ASSETS=PASS')
PY
python3 scripts/extract-reference-assets.py
ok "artes reais da referencia extraidas"

section "4. CORRIGINDO O APLICATIVO NATIVO PARA USAR A MESMA IDENTIDADE VISUAL"
python3 <<'PY'
from pathlib import Path
import re, json

p=Path('App.tsx')
s=p.read_text(encoding='utf-8')

assets="""
const REFERENCE_BASE = 'https://www.radio.studiosatweb.com.br/listen/reference';
const REFERENCE_ASSETS = {
  hero: `${REFERENCE_BASE}/hero-reference.jpg`,
  artist: `${REFERENCE_BASE}/artist-reference.jpg`,
  promo: `${REFERENCE_BASE}/promo-reference.jpg`,
  stations: {
    radioprincipal: `${REFERENCE_BASE}/station-principal.jpg`,
    radiopop: `${REFERENCE_BASE}/station-pop.jpg`,
    radiorock: `${REFERENCE_BASE}/station-rock.jpg`,
    radioclassicas: `${REFERENCE_BASE}/station-classicas.jpg`,
    radiocountry: `${REFERENCE_BASE}/station-country.jpg`,
  } as Record<StationId, string>,
};
"""
if 'const REFERENCE_BASE' not in s:
    s=s.replace("const emptyNow: NowPlaying = {", assets+"\nconst emptyNow: NowPlaying = {",1)

station_fn="""function StationCard({ station, active, onPress }: { station: Station; active: boolean; onPress: () => void }) {
  const imageUrl = REFERENCE_ASSETS.stations[station.id];
  return (
    <Pressable onPress={onPress} style={[styles.stationCardOuter, active && styles.stationCardOuterActive]}>
      <View style={styles.stationCard}>
        <Image source={{ uri: imageUrl }} style={StyleSheet.absoluteFill} resizeMode=\"cover\" />
        <LinearGradient colors={['rgba(6,13,42,0.02)','rgba(6,13,42,0.20)','rgba(6,13,42,0.86)']} locations={[0,0.45,1]} style={StyleSheet.absoluteFill} />
        <View style={{ flex: 1, justifyContent: 'flex-end', zIndex: 2 }}>
          <Text style={styles.stationCardLabel}>{station.shortName.toUpperCase()}</Text>
        </View>
      </View>
    </Pressable>
  );
}
"""
s2,n=re.subn(r"function StationCard\([\s\S]*?\n}\n\nfunction BottomTab", station_fn+"\nfunction BottomTab", s, count=1)
if n!=1:
    raise SystemExit('ERRO: nao foi possivel substituir StationCard')
s=s2

old='{cover ? <Image source={{ uri: cover }} style={StyleSheet.absoluteFill} resizeMode="cover" /> : null}'
new='<Image source={{ uri: cover || REFERENCE_ASSETS.hero }} style={StyleSheet.absoluteFill} resizeMode="cover" />'
if old in s:
    s=s.replace(old,new,1)
elif 'REFERENCE_ASSETS.hero' not in s:
    raise SystemExit('ERRO: hero nativo nao localizado')

old2='{cover ? <Image source={{ uri: cover }} style={styles.artistAvatarImage} /> : <Text style={styles.artistAvatarText}>SS</Text>}'
new2='<Image source={{ uri: cover || REFERENCE_ASSETS.artist }} style={styles.artistAvatarImage} resizeMode="cover" />'
if old2 in s:
    s=s.replace(old2,new2,1)
elif 'REFERENCE_ASSETS.artist' not in s:
    raise SystemExit('ERRO: avatar nativo nao localizado')

# Ajuste de proporcoes para ficar mais perto da referencia aprovada.
repls={
 "hero: { minHeight: 470,":"hero: { minHeight: 392,",
 "heroContent: { flex: 1, padding: 20, paddingTop: 18 }":"heroContent: { flex: 1, padding: 15, paddingTop: 15 }",
 "heroTitle: { color: '#FFFFFF', fontSize: 42, lineHeight: 39":"heroTitle: { color: '#FFFFFF', fontSize: 37, lineHeight: 35",
 "playButtonOuter: { width: 84, height: 84, borderRadius: 42":"playButtonOuter: { width: 78, height: 78, borderRadius: 39",
 "playButton: { width: 72, height: 72, borderRadius: 36":"playButton: { width: 64, height: 64, borderRadius: 32",
 "translationCard: { marginTop: 12":"translationCard: { marginTop: 10",
 "stationCardOuter: { width: 88, height: 92":"stationCardOuter: { width: 72, height: 91",
}
for a,b in repls.items():
    s=s.replace(a,b)

p.write_text(s,encoding='utf-8')

m=Path('src/components/MediaCarousel.tsx')
ms=m.read_text(encoding='utf-8')
ms=ms.replace("url: '',\n        eyebrow: 'PUBLICIDADE',","url: 'https://www.radio.studiosatweb.com.br/listen/reference/promo-reference.jpg',\n        eyebrow: 'PUBLICIDADE',")
ms=ms.replace("height: 182,","height: 158,")
m.write_text(ms,encoding='utf-8')

# Versao real do app.
app=Path('app.json')
data=json.loads(app.read_text(encoding='utf-8'))
data['expo']['version']='1.2.0'
app.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
pkg=Path('package.json')
pdata=json.loads(pkg.read_text(encoding='utf-8'))
pdata['version']='1.2.0'
pkg.write_text(json.dumps(pdata,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

print('NATIVE_UI_PATCH=PASS')
PY
ok "app nativo usa hero, artista, publicidade e emissores da referencia"

section "5. RECONSTRUINDO A CENTRAL /app/ COMO INSTALADOR REAL + PREVIEW REAL"
cat > web/download/index.html <<'HTML'
<!doctype html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<meta name="theme-color" content="#f4f7ff">
<title>Instalar Radio Studio Sat</title>
<style>
:root{--ink:#162451;--muted:#667594;--line:#d9e2f1;--blue:#2f64ff;--red:#ff3158;--bg:#edf3ff}
*{box-sizing:border-box}body{margin:0;font-family:Inter,system-ui,-apple-system,Segoe UI,sans-serif;color:var(--ink);background:radial-gradient(circle at 10% 0,#fff 0,transparent 35%),radial-gradient(circle at 90% 10%,#ece6ff 0,transparent 30%),var(--bg)}
.wrap{width:min(1180px,94vw);margin:auto}.top{display:flex;align-items:center;padding:22px 0}.brand{font-weight:950;font-size:20px}.brand small{display:block;font-size:8px;letter-spacing:2px;color:var(--muted);margin-top:3px}.portal{margin-left:auto;text-decoration:none;color:#415785;font-weight:800}.layout{display:grid;grid-template-columns:minmax(0,1fr) 430px;gap:44px;align-items:start;padding:18px 0 40px}.eyebrow{font-size:11px;letter-spacing:1.6px;font-weight:950;color:var(--blue)}h1{font-size:clamp(42px,6vw,78px);line-height:.94;letter-spacing:-3px;margin:10px 0 16px}.lead{font-size:17px;line-height:1.6;color:var(--muted);max-width:680px}.detected{margin:22px 0 16px;padding:16px 18px;border-radius:18px;background:#162451;color:white}.detected b{font-size:17px}.detected span{display:block;font-size:12px;opacity:.75;margin-top:4px}.primary{display:inline-flex;min-height:52px;align-items:center;justify-content:center;padding:0 20px;border-radius:15px;background:linear-gradient(135deg,#31bfff,#665cf8,#e942d7);color:#fff;text-decoration:none;font-weight:950;box-shadow:0 12px 26px rgba(78,93,220,.22)}.secondary{display:inline-flex;min-height:52px;align-items:center;justify-content:center;padding:0 20px;border-radius:15px;border:1px solid var(--line);background:#fff;color:var(--ink);text-decoration:none;font-weight:900}.actions{display:flex;gap:10px;flex-wrap:wrap}.platforms{display:grid;grid-template-columns:repeat(2,1fr);gap:10px;margin-top:18px}.platform{background:#fff;border:1px solid var(--line);border-radius:16px;padding:13px}.platform b{display:block;font-size:13px}.platform small{display:block;color:var(--muted);line-height:1.35;margin-top:4px}.previewShell{position:sticky;top:12px;border-radius:36px;padding:9px;background:#10172f;box-shadow:0 26px 65px rgba(32,47,110,.24)}.previewShell iframe{width:100%;height:820px;border:0;border-radius:29px;background:#fff;display:block}.caption{text-align:center;color:var(--muted);font-size:11px;margin-top:10px}.foot{border-top:1px solid var(--line);padding:20px 0 32px;color:var(--muted);font-size:12px}@media(max-width:900px){.layout{grid-template-columns:1fr}.previewShell{position:relative;width:min(430px,100%);margin:auto}.platforms{grid-template-columns:1fr 1fr}}@media(max-width:560px){.platforms{grid-template-columns:1fr}.previewShell{padding:0;background:transparent;box-shadow:none}.previewShell iframe{height:760px;border-radius:0}.wrap{width:min(100%,94vw)}h1{letter-spacing:-2px}}
</style>
</head>
<body>
<header class="wrap top"><div class="brand">Studio Sat<small>A MÚSICA NOS CONECTA</small></div><a class="portal" href="/">Portal →</a></header>
<main class="wrap layout">
<section>
<div class="eyebrow">CENTRAL OFICIAL DE INSTALAÇÃO</div>
<h1>O aplicativo<br>que você vê<br>é o que instala.</h1>
<p class="lead">A prévia ao lado é o próprio Web App funcional da Studio Sat. Android recebe o APK nativo; Windows e iPhone usam a mesma interface instalada como PWA; Smart TV abre a versão web adaptada.</p>
<div class="detected"><b id="deviceTitle">Detectando seu dispositivo…</b><span id="deviceText">Preparando a opção correta.</span></div>
<div class="actions"><a id="mainAction" class="primary" href="/listen/">Abrir Studio Sat</a><a id="altAction" class="secondary" href="/listen/">Usar no navegador</a></div>
<div class="platforms">
<div class="platform"><b>Android</b><small>APK nativo oficial: @@VERSION@@.</small></div>
<div class="platform"><b>iPhone / iPad</b><small>Safari → Compartilhar → Adicionar à Tela de Início. Versão nativa depende de Apple Developer.</small></div>
<div class="platform"><b>Windows</b><small>Edge/Chrome: PWA instalável com a mesma interface.</small></div>
<div class="platform"><b>Smart TV</b><small>Web App em tela grande; pacotes Tizen/webOS podem ser gerados separadamente.</small></div>
</div>
</section>
<section><div class="previewShell"><iframe src="/listen/?preview=installer" title="Prévia real do aplicativo Studio Sat" allow="autoplay"></iframe></div><div class="caption">PREVIEW REAL — /listen/</div></section>
</main>
<footer class="foot"><div class="wrap">© @@YEAR@@ Studio Sat Web · Cinco rádios em um só aplicativo.</div></footer>
<script>
(()=>{const ua=navigator.userAgent||'',plat=navigator.platform||'';const t=document.getElementById('deviceTitle'),d=document.getElementById('deviceText'),a=document.getElementById('mainAction'),b=document.getElementById('altAction');if(/Android/i.test(ua)&&!/TV|BRAVIA|AFT|SHIELD/i.test(ua)){t.textContent='Android detectado';d.textContent='Instalação recomendada: APK nativo Studio Sat.';a.textContent='Baixar APK Android';a.href='@@APK_URL@@';a.setAttribute('download','RadioStudioSat-@@VERSION@@.apk')}else if(/iPhone|iPad|iPod/i.test(ua)){t.textContent='iPhone / iPad detectado';d.textContent='Abra no Safari e adicione à Tela de Início.';a.textContent='Abrir no iPhone';a.href='/listen/';b.textContent='Como instalar';b.href='#';b.onclick=e=>{e.preventDefault();alert('No Safari: toque em Compartilhar e depois em Adicionar à Tela de Início.')}}else if(/Windows/i.test(ua)||/Win/i.test(plat)){t.textContent='Windows detectado';d.textContent='Abra o Web App e use Instalar no Edge ou Chrome.';a.textContent='Abrir / instalar no Windows';a.href='/listen/'}else if(/TV|BRAVIA|AFT|SHIELD|Tizen|webOS|SMART-TV|HbbTV|NetCast|Viera/i.test(ua)){t.textContent='Smart TV detectada';d.textContent='Abrindo a interface preparada para TV.';a.textContent='Abrir na TV';a.href='/listen/?tv=1'}else{t.textContent='Navegador detectado';d.textContent='Use o Web App Studio Sat.'}})();
</script>
</body></html>
HTML
ok "central de instalacao reconstruida com preview real"

section "6. VALIDACAO LOCAL DE CODIGO"
node scripts/validate-pwa.mjs
npm install --no-audit --no-fund
npx --yes expo-doctor
npm run typecheck
ok "PWA + Expo Doctor + TypeScript"

section "7. COMMITANDO A RECONSTRUCAO ANTES DO BUILD"
if [[ -n "$(git status --porcelain)" ]]; then
  git add App.tsx src/components/MediaCarousel.tsx web/download/index.html web/pwa/reference scripts/extract-reference-assets.py app.json package.json
  git commit -m "Rebuild Studio Sat UI and universal installer v$VERSION"
  git push origin main
  ok "reconstrucao salva no GitHub"
else
  echo "INFO: nenhum arquivo novo para commit"
fi

section "8. DEPLOY WEB/PWA/INSTALADOR NO NS1"
VERSION="$VERSION" bash scripts/sync-and-deploy-universal.sh
ok "web/PWA publicado"

section "9. VALIDACAO VISUAL E HTTP ANTES DO APK"
for u in "/app/" "/listen/" "/listen/reference/hero-reference.jpg" "/listen/reference/promo-reference.jpg"; do
  code="$(curl -ksS -o /tmp/studiosat-check -w '%{http_code}' "$PUBLIC_HOST$u")"
  [[ "$code" == "200" ]] || fail "$u HTTP=$code"
  echo "PASS  $u HTTP=200"
done
curl -ksS "$PUBLIC_HOST/app/" | grep -q 'O aplicativo' || fail "/app/ ainda nao recebeu o instalador novo"
curl -ksS "$PUBLIC_HOST/listen/" | grep -q 'A MÚSICA NOS CONECTA' || fail "/listen/ ainda nao recebeu a UI referencia"
ok "instalador e aplicativo web coerentes"

section "10. AUTENTICACAO EAS"
WHO="$(npx --yes eas-cli@latest whoami 2>&1 || true)"
printf '%s\n' "$WHO"
[[ -n "$WHO" ]] && ! grep -qiE 'not logged|error' <<<"$WHO" || fail "EAS nao autenticado. Execute: npx eas-cli@latest login"
ok "EAS autenticado"

section "11. BUILD ANDROID NATIVO $VERSION"
VERSION="$VERSION" bash scripts/build-release.sh preview
ok "build EAS Android finalizado"

section "12. BAIXANDO E PUBLICANDO O APK EXATO"
VERSION="$VERSION" bash scripts/finalize-latest-apk.sh
APK="/root/builds/RadioStudioSat-v${VERSION}.apk"
[[ -f "$APK" ]] || fail "APK final nao encontrado: $APK"
file "$APK"
unzip -t "$APK" >/dev/null
SHA="$(sha256sum "$APK" | awk '{print $1}')"
SIZE="$(stat -c %s "$APK")"
(( SIZE > 10000000 )) || fail "APK pequeno demais: $SIZE"
ok "APK validado sha256=$SHA bytes=$SIZE"

section "13. REPUBLICANDO CENTRAL COM APK $VERSION"
VERSION="$VERSION" APK_SOURCE="$APK" bash scripts/deploy-download-page.sh
VERSION="$VERSION" APK_SOURCE="$APK" bash scripts/deploy-universal-platforms.sh
ok "installer atualizado para o APK novo"

if [[ "$BUILD_IOS" == "1" ]]; then
  section "14. BUILD IOS OPCIONAL"
  echo "BUILD_IOS=1 solicitado. Esta etapa exige credenciais Apple Developer validas."
  npx --yes eas-cli@latest build --platform ios --profile preview --non-interactive --wait
  ok "build iOS solicitado/concluido"
fi

section "15. TESTE FINAL PUBLICO"
APP_H="$(curl -ksSI "$PUBLIC_HOST/app/" | tr -d '\r')"
LISTEN_H="$(curl -ksSI "$PUBLIC_HOST/listen/" | tr -d '\r')"
APK_H="$(curl -ksSI "$PUBLIC_HOST/downloads/apps/RadioStudioSat-latest.apk" | tr -d '\r')"
grep -qiE '^HTTP/(2|1\.1) 200' <<<"$APP_H" || fail "/app/ publico"
grep -qiE '^HTTP/(2|1\.1) 200' <<<"$LISTEN_H" || fail "/listen/ publico"
grep -qiE '^HTTP/(2|1\.1) 200' <<<"$APK_H" || fail "APK publico"
grep -qi '^content-type: application/vnd.android.package-archive' <<<"$APK_H" || fail "APK content-type"
for id in radioprincipal radiopop radiorock radioclassicas radiocountry; do
  code="$(curl -ksSL --max-redirs 6 -o /tmp/$id.m3u8 -w '%{http_code}' "$STREAM_HOST/$id/index.m3u8")"
  [[ "$code" == "200" ]] && grep -q '#EXTM3U' "/tmp/$id.m3u8" || fail "stream $id"
  echo "PASS  $id"
done
nginx -t

printf '\n============================================================\n'
printf 'STUDIOSAT_FINAL_REBUILD=PASS\n'
printf 'VERSION=%s\n' "$VERSION"
printf 'HEAD=%s\n' "$(git rev-parse HEAD)"
printf 'INSTALLER=%s/app/\n' "$PUBLIC_HOST"
printf 'WEB_APP=%s/listen/\n' "$PUBLIC_HOST"
printf 'ANDROID_APK=%s/downloads/apps/RadioStudioSat-latest.apk\n' "$PUBLIC_HOST"
printf 'APK_LOCAL=%s\n' "$APK"
printf 'APK_SHA256=%s\n' "$SHA"
printf 'WINDOWS=PWA\n'
printf 'IPHONE=PWA_SAFARI\n'
printf 'IOS_NATIVE=%s\n' "$([[ "$BUILD_IOS" == "1" ]] && echo REQUESTED || echo NOT_BUILT_REQUIRES_APPLE_DEVELOPER)"
printf 'BACKUP=%s\n' "$BACKUP"
printf '============================================================\n'
