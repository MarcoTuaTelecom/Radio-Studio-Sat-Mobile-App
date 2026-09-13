import fs from 'node:fs';
import crypto from 'node:crypto';
import zlib from 'node:zlib';

const BROKEN_GIT_BLOB_SHA = '17827d97bd4273633632cb63404a788bfad9983d';
const force = process.env.STUDIOSAT_REGENERATE_ASSETS === '1';

const crcTable = (() => {
  const table = new Uint32Array(256);
  for (let n = 0; n < 256; n += 1) {
    let c = n;
    for (let k = 0; k < 8; k += 1) c = (c & 1) ? (0xedb88320 ^ (c >>> 1)) : (c >>> 1);
    table[n] = c >>> 0;
  }
  return table;
})();

function crc32(buffer) {
  let c = 0xffffffff;
  for (const byte of buffer) c = crcTable[(c ^ byte) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

function chunk(type, data) {
  const typeBuf = Buffer.from(type, 'ascii');
  const body = Buffer.concat([typeBuf, data]);
  const out = Buffer.alloc(12 + data.length);
  out.writeUInt32BE(data.length, 0);
  typeBuf.copy(out, 4);
  data.copy(out, 8);
  out.writeUInt32BE(crc32(body), 8 + data.length);
  return out;
}

function png(width, height, channels, pixel) {
  const colorType = channels === 4 ? 6 : 2;
  const stride = width * channels + 1;
  const raw = Buffer.alloc(stride * height);
  for (let y = 0; y < height; y += 1) {
    const row = y * stride;
    raw[row] = 0; // PNG filter 0: standards-compliant and Jimp-safe
    for (let x = 0; x < width; x += 1) {
      const rgba = pixel(x, y, width, height);
      const o = row + 1 + x * channels;
      raw[o] = rgba[0]; raw[o + 1] = rgba[1]; raw[o + 2] = rgba[2];
      if (channels === 4) raw[o + 3] = rgba[3] ?? 255;
    }
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8;
  ihdr[9] = colorType;
  ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;
  return Buffer.concat([
    Buffer.from([137,80,78,71,13,10,26,10]),
    chunk('IHDR', ihdr),
    chunk('IDAT', zlib.deflateSync(raw, { level: 9 })),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

function clamp(v) { return Math.max(0, Math.min(255, Math.round(v))); }

function studioMark(x, y, w, h, mode) {
  const nx = (x - w / 2) / w;
  const ny = (y - h / 2) / h;
  const r = Math.hypot(nx, ny);

  if (mode === 'adaptive' && r > 0.35) return [0, 0, 0, 0];

  let bg;
  if (mode === 'splash') {
    bg = [246, 248, 252, 255];
  } else {
    const t = y / Math.max(1, h - 1);
    bg = [clamp(15 + 12 * t), clamp(23 + 14 * t), clamp(42 + 35 * t), 255];
  }

  const disc = mode === 'adaptive' ? 0.33 : 0.31;
  if (r < disc) {
    const t = (nx + ny + 0.65) / 1.3;
    bg = [clamp(91 + 33 * t), clamp(103 - 20 * t), clamp(242 - 17 * t), 255];
  }

  // Equalizer mark in the center: five white bars, symmetric and readable at small sizes.
  const barXs = [-0.12, -0.06, 0, 0.06, 0.12];
  const heights = [0.10, 0.17, 0.23, 0.17, 0.10];
  for (let i = 0; i < barXs.length; i += 1) {
    const halfW = 0.017;
    const halfH = heights[i] / 2;
    if (Math.abs(nx - barXs[i]) <= halfW && Math.abs(ny) <= halfH) return [255, 255, 255, 255];
  }

  // Thin orbit around the mark.
  if (Math.abs(r - 0.37) < 0.008 && Math.abs(ny) < 0.22) {
    return mode === 'splash' ? [91, 103, 242, 255] : [210, 217, 255, 255];
  }

  return bg;
}

function gitBlobSha(buffer) {
  return crypto.createHash('sha1').update(`blob ${buffer.length}\0`).update(buffer).digest('hex');
}

function writeAsset(path, width, height, channels, mode) {
  let replace = force || !fs.existsSync(path);
  if (!replace) {
    const old = fs.readFileSync(path);
    replace = gitBlobSha(old) === BROKEN_GIT_BLOB_SHA;
  }
  if (!replace) {
    console.log(`KEEP  ${path}`);
    return;
  }
  const data = png(width, height, channels, (x, y, w, h) => studioMark(x, y, w, h, mode));
  fs.writeFileSync(path, data);
  console.log(`FIXED ${path} ${width}x${height} sha256=${crypto.createHash('sha256').update(data).digest('hex')}`);
}

fs.mkdirSync('assets', { recursive: true });
writeAsset('assets/icon.png', 1024, 1024, 4, 'icon');
writeAsset('assets/adaptive-icon.png', 1024, 1024, 4, 'adaptive');
writeAsset('assets/splash.png', 1024, 1024, 4, 'splash');
writeAsset('assets/favicon.png', 512, 512, 4, 'icon');
