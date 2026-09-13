import { Station } from '../types';

const PLAYER = 'https://radio.studiosatweb.com.br';

export const STATIONS: Station[] = [
  {
    id: 'radioprincipal',
    name: 'Radio Studio Sat',
    shortName: 'Principal',
    description: 'Grandes sucessos e programação principal',
    streamUrl: `${PLAYER}/radioprincipal/index.m3u8`,
    metadataUrl: `${PLAYER}/assets/now/radioprincipal.json`,
    accent: '#5B66F2',
    softAccent: '#EEF0FF',
  },
  {
    id: 'radiopop',
    name: 'Radio Studio Sat Pop',
    shortName: 'Pop',
    description: 'Hits, lançamentos e cultura pop',
    streamUrl: `${PLAYER}/radiopop/index.m3u8`,
    metadataUrl: `${PLAYER}/assets/now/radiopop.json`,
    accent: '#D84BA6',
    softAccent: '#FBEAF6',
  },
  {
    id: 'radiorock',
    name: 'Radio Studio Sat Rock',
    shortName: 'Rock',
    description: 'Clássicos, novidades e atitude',
    streamUrl: `${PLAYER}/radiorock/index.m3u8`,
    metadataUrl: `${PLAYER}/assets/now/radiorock.json`,
    accent: '#596175',
    softAccent: '#EEF0F4',
  },
  {
    id: 'radioclassicas',
    name: 'Radio Studio Sat Clássicas',
    shortName: 'Clássicas',
    description: 'Música clássica e obras essenciais',
    streamUrl: `${PLAYER}/radioclassicas/index.m3u8`,
    metadataUrl: `${PLAYER}/assets/now/radioclassicas.json`,
    accent: '#B7791F',
    softAccent: '#FFF6E6',
  },
  {
    id: 'radiocountry',
    name: 'Radio Studio Sat Country',
    shortName: 'Country',
    description: 'Country, raízes e novos nomes',
    streamUrl: `${PLAYER}/radiocountry/index.m3u8`,
    metadataUrl: `${PLAYER}/assets/now/radiocountry.json`,
    accent: '#2F8F63',
    softAccent: '#EAF7F1',
  },
];

export const DEFAULT_STATION = STATIONS[0]!;
