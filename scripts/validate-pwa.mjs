import fs from 'node:fs';
import path from 'node:path';

const root = process.cwd();
const htmlPath = path.join(root, 'web/pwa/index.html');
const html = fs.readFileSync(htmlPath, 'utf8');

const required = [
  '<title>Radio Studio Sat</title>',
  'A MÚSICA NOS CONECTA',
  'TRADUÇÃO',
  'Nossas Emissoras',
  'hero-studiosat.svg',
  'promo-sunset.svg',
  'station-principal.svg',
  'station-pop.svg',
  'station-rock.svg',
  'station-classicas.svg',
  'station-country.svg',
  'beforeinstallprompt',
  'createAnalyser',
  'mediaSession',
  'for(let i=0;i<30;i++)',
];
for (const marker of required) {
  if (!html.includes(marker)) throw new Error(`PWA marker ausente: ${marker}`);
}

const inlineScripts = [...html.matchAll(/<script(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/gi)].map((m) => m[1]);
if (!inlineScripts.length) throw new Error('Nenhum JavaScript inline encontrado no PWA');
for (const [index, code] of inlineScripts.entries()) {
  try {
    new Function(code);
  } catch (error) {
    console.error(`Falha de sintaxe no script inline #${index + 1}`);
    throw error;
  }
}

const ids = [...html.matchAll(/\bid="([^"]+)"/g)].map((m) => m[1]);
const duplicateIds = ids.filter((id, index) => ids.indexOf(id) !== index);
if (duplicateIds.length) throw new Error(`IDs HTML duplicados: ${[...new Set(duplicateIds)].join(', ')}`);

const assets = [
  'hero-studiosat.svg',
  'promo-sunset.svg',
  'station-principal.svg',
  'station-pop.svg',
  'station-rock.svg',
  'station-classicas.svg',
  'station-country.svg',
];
for (const asset of assets) {
  const p = path.join(root, 'web/pwa/art', asset);
  if (!fs.existsSync(p)) throw new Error(`Asset ausente: ${p}`);
  const text = fs.readFileSync(p, 'utf8');
  if (!text.includes('<svg')) throw new Error(`Asset SVG invalido: ${asset}`);
}

console.log('PWA_HTML_JS=PASS');
console.log(`INLINE_SCRIPTS=${inlineScripts.length}`);
console.log(`HTML_IDS=${ids.length}`);
console.log(`ART_ASSETS=${assets.length}`);
