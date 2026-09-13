# Studio Sat Mobile — contrato de integração

O aplicativo usa a infraestrutura real das cinco rádios e não cria um segundo sistema de playout.

## Streaming HLS

Base pública:

`https://radio.studiosatweb.com.br/<station-id>/index.m3u8`

IDs canônicos:

- `radioprincipal`
- `radiopop`
- `radiorock`
- `radioclassicas`
- `radiocountry`

## Now Playing

O app consulta a cada 8 segundos:

`GET https://radio.studiosatweb.com.br/assets/now/<station-id>.json`

Payload suportado:

```json
{
  "station": "Radio Studio Sat",
  "program": "Hits da Manhã",
  "presenter": "Nome do locutor",
  "artist": "Artista",
  "track": "Música",
  "cover": "https://.../capa.webp",
  "startedAt": "2026-09-12T22:00:00-03:00",
  "duration": 223,
  "revision": 42,
  "translationPtBr": "Texto editorial/tradução licenciada"
}
```

Campos ausentes não derrubam o player; a UI entra em fallback.

## VU real

O VU não depende do metadata. `expo-audio` entrega amostras PCM do áudio reproduzido e o app calcula RMS suavizado em tempo real. No Android, a API exige a permissão `RECORD_AUDIO` para liberar audio sampling; o app não inicia gravação de microfone.

## Carrossel no box

O app consulta:

`GET https://www.radio.studiosatweb.com.br/api/content`

Ele combina `hero[]` e `news[]` da emissora ativa. Cada item pode ser imagem ou vídeo:

```json
{
  "id": "campanha-estreia",
  "type": "video",
  "url": "/uploads/estreia.mp4",
  "eyebrow": "PUBLICIDADE",
  "headline": "Studio Sat — cinco rádios em um app",
  "caption": "14/09/2026 às 10:00",
  "durationMs": 10000
}
```

O vídeo roda **mudo** dentro do box para nunca competir com o áudio da rádio. Imagens e vídeos avançam automaticamente e voltam ao primeiro item.

## Segurança

Nenhum token administrativo, senha, stream key ou segredo deve entrar no app. O aplicativo só consome endpoints públicos de leitura.
