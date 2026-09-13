export type StationId =
  | 'radioprincipal'
  | 'radiopop'
  | 'radiorock'
  | 'radioclassicas'
  | 'radiocountry';

export type Station = {
  id: StationId;
  name: string;
  shortName: string;
  description: string;
  streamUrl: string;
  metadataUrl: string;
  accent: string;
  softAccent: string;
};

export type NowPlaying = {
  station?: string;
  program?: string;
  presenter?: string;
  artist?: string;
  track?: string;
  cover?: string;
  startedAt?: string;
  duration?: number;
  revision?: string | number;
  translation?: string;
  translationPtBr?: string;
};

export type CarouselItem = {
  id: string;
  type: 'image' | 'video';
  url: string;
  headline?: string;
  eyebrow?: string;
  caption?: string;
  durationMs?: number;
};

export type PortalContentStation = {
  id: StationId;
  hero?: Array<Record<string, unknown>>;
  news?: Array<Record<string, unknown>>;
};
