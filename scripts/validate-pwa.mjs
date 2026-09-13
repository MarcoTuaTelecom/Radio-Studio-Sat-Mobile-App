import fs from 'node:fs';
import path from 'node:path';

const root = process.cwd();
const htmlPath = path.join(root, 'web/pwa/index.html');
const html = fs.readFileSync(htmlPath, 'utf8');

const required = [
  '<title>Radio Studio Sat</title>',
  'A MÚSICA NOS CONECTA',
  'AO VIVO',
  'TRADUÇÃO',
  'Nossas Emissoras',
  'Música boa em todos os momentos',
  'data:image/jpeg;base64,',
  'stationImgs',
  'createAnalyser',
  'mediaSession',
  'for(let i=0;i<30;i++)',
  'position:sticky',
  "navigator.serviceWorker.register('/listen/sw.js')",
];
for (const marker of required) {
  if (!html.includes(marker)) throw new Error(`PWA marker ausente: ${marker}`);
}

const embeddedJpegs = [...html.matchAll(/data:image\/jpeg;base64,([A-Za-z0-9+/=]+)/g)];
if (embeddedJpegs.length < 8) throw new Error(`Esperava ao menos 8 JPEGs embutidos; encontrei ${embeddedJpegs.length}`);

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

const stationIds = ['radioprincipal','radiopop','radiorock','radioclassicas','radiocountry'];
for (const station of stationIds) {
  if (!html.includes(station)) throw new Error(`Emissora ausente: ${station}`);
}

console.log('PWA_HTML_JS=PASS');
console.log(`INLINE_SCRIPTS=${inlineScripts.length}`);
console.log(`HTML_IDS=${ids.length}`);
console.log(`EMBEDDED_JPEGS=${embeddedJpegs.length}`);
console.log(`STATIONS=${stationIds.length}`);
