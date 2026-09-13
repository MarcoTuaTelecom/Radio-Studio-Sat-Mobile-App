import { CarouselItem, NowPlaying, PortalContentStation, Station } from '../types';

const CONTENT_API = 'https://www.radio.studiosatweb.com.br/api/content';
const PUBLIC_ROOT = 'https://www.radio.studiosatweb.com.br';

const absolutize = (url?: string): string | undefined => {
  if (!url) return undefined;
  if (/^https?:\/\//i.test(url)) return url;
  return `${PUBLIC_ROOT}${url.startsWith('/') ? '' : '/'}${url}`;
};

export async function fetchNowPlaying(station: Station): Promise<NowPlaying> {
  const response = await fetch(`${station.metadataUrl}?t=${Date.now()}`, {
    headers: { Accept: 'application/json' },
    cache: 'no-store',
  });
  if (!response.ok) throw new Error(`metadata_http_${response.status}`);
  const data = (await response.json()) as NowPlaying;
  return {
    ...data,
    cover: absolutize(data.cover),
  };
}

function normalizeCarouselRecord(record: Record<string, unknown>, index: number): CarouselItem | null {
  const rawUrl = String(record.url ?? record.media ?? record.src ?? '').trim();
  if (!rawUrl) return null;
  const kind = String(record.type ?? '').toLowerCase();
  const type: 'image' | 'video' = kind === 'video' || /\.(mp4|m4v|mov|webm)(\?|$)/i.test(rawUrl) ? 'video' : 'image';
  return {
    id: String(record.id ?? `${type}-${index}`),
    type,
    url: absolutize(rawUrl)!,
    headline: record.headline ? String(record.headline) : record.title ? String(record.title) : undefined,
    eyebrow: record.eyebrow ? String(record.eyebrow) : record.category ? String(record.category) : undefined,
    caption: record.caption ? String(record.caption) : record.summary ? String(record.summary) : undefined,
    durationMs: Number(record.durationMs ?? 9000),
  };
}

export async function fetchCarousel(stationId: string): Promise<CarouselItem[]> {
  const response = await fetch(`${CONTENT_API}?t=${Date.now()}`, {
    headers: { Accept: 'application/json' },
    cache: 'no-store',
  });
  if (!response.ok) throw new Error(`content_http_${response.status}`);
  const body = (await response.json()) as { stations?: PortalContentStation[] };
  const station = body.stations?.find((item) => item.id === stationId);
  if (!station) return [];
  const records = [...(station.hero ?? []), ...(station.news ?? [])];
  return records
    .map((record, index) => normalizeCarouselRecord(record, index))
    .filter((item): item is CarouselItem => Boolean(item));
}
