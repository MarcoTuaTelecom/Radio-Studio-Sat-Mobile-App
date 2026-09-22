# Documentação técnica completa — Studio Sat Native V2

# Arquitetura — Studio Sat Native V2

## Objetivo arquitetural

Separar radicalmente três responsabilidades:

1. **Origem de mídia** — FFmpeg/servidor produz HLS.
2. **Metadados** — API Rust entrega nomes, programação, notícias e promoções.
3. **Reprodução** — mecanismo nativo da plataforma recebe a URL HLS.

Nenhuma camada editorial fica entre o HLS e o decoder.

## Web

```text
Nginx/HLS
   ↓
HTMLAudioElement
   ↓
[HLS nativo ou HLS.js/MSE]
   ↓
decoder do navegador/SO
```

O Rust/WASM controla apenas UI e chamadas REST.

## Android

```text
Nginx/HLS
   ↓
Media3 HLS MediaSource
   ↓
ExoPlayer
   ↓
MediaCodec / AudioTrack
```

O app não instala `AudioEffect` e não amostra áudio.

## iOS

```text
Nginx/HLS
   ↓
AVPlayerItem
   ↓
AVPlayer
   ↓
AVFoundation/CoreAudio
```

O app não usa `AVAudioEngine` e não instala taps.

## API

A API Axum lê dados em JSON por desenho inicial. Isso permite substituir o
backend editorial depois sem alterar o player.

## Contrato de streams

Os endpoints públicos de mídia continuam estáveis:

- `https://radio.studiosatweb.com.br/radioprincipal/index.m3u8`
- `https://radio.studiosatweb.com.br/radiopop/index.m3u8`
- `https://radio.studiosatweb.com.br/radiorock/index.m3u8`
- `https://radio.studiosatweb.com.br/radioclassicas/index.m3u8`
- `https://radio.studiosatweb.com.br/radiocountry/index.m3u8`


---

# Caminho de mídia

## Regra invariável

O cliente deve alterar o mínimo possível o stream.

### Proibido no caminho audível

- WebAudio `AudioContext`
- `AnalyserNode`
- VU por leitura de samples
- `currentTime` ajustado periodicamente
- `playbackRate` usado para perseguir live edge
- normalização ou limiter no cliente
- nova codificação do áudio
- transformação estéreo
- reamostragem criada pelo aplicativo

### Permitido

- demux HLS
- buffer de rede
- decoder AAC do sistema
- controle de volume final
- pausa/play
- metadados de Media Session

## Web e HLS.js

HLS.js é usado apenas onde `<audio>` não suporta HLS nativo. A configuração é
intencionalmente conservadora:

- `lowLatencyMode: false`
- `maxLiveSyncPlaybackRate: 1.0`
- sem código de `currentTime`
- sem AudioContext

## VU

O VU é decorativo. Ele indica estado "tocando" e nunca lê o áudio.


---

# ADR-001 — Caminho de mídia limpo

Status: aprovado para V2.

## Contexto

O sistema legado apresentou aceleração, desaceleração, silêncio temporário e
liberação posterior de áudio acumulado enquanto streams HLS diretos eram
reproduzidos corretamente fora do portal/app.

## Decisão

Construir clientes novos em que o stream HLS seja entregue diretamente ao
mecanismo de mídia da plataforma.

## Consequências

- VU deixa de representar amplitude real.
- Não existe DSP no cliente.
- Metadados passam por API separada.
- Erros de UI não devem degradar o stream.
- Portal V2 será publicado em paralelo antes do cutover.


---

# Compilação

## Linux / portal / API

Pré-requisitos:

- curl
- gcc/clang e linker
- pkg-config
- rsync
- Rust stable
- wasm-pack

Automático:

```bash
bash scripts/bootstrap-linux.sh
bash scripts/build-linux.sh
```

Saídas:

```text
dist/api/studiosat-api
dist/web/
```

## Android

Pré-requisitos:

- JDK 21
- Android SDK 37
- Gradle compatível com AGP 9.4

```bash
cd android
gradle :app:assembleDebug
```

## iOS

Requer macOS/Xcode.

```bash
brew install xcodegen
cd ios
xcodegen generate
xcodebuild \
  -project StudioSat.xcodeproj \
  -scheme StudioSat \
  -sdk iphonesimulator \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  build
```


---

# Implantação no NS1

A V2 não substitui o portal legado durante a fase de validação.

## 1. Build

```bash
bash scripts/bootstrap-linux.sh
bash scripts/build-linux.sh
```

## 2. Instalação

```bash
sudo bash deploy/install-ns1.sh
```

O instalador cria:

```text
/opt/studiosat-v2/bin/studiosat-api
/etc/studiosat-v2/data/
/var/www/studiosat-v2/listen/
/etc/systemd/system/studiosat-api-v2.service
```

Também insere, no vhost de `www.radio.studiosatweb.com.br`, os locations:

```text
/listen-v2/
/api/v2/
```

## 3. Testes

```bash
curl -i https://www.radio.studiosatweb.com.br/api/v2/health
curl -i https://www.radio.studiosatweb.com.br/api/v2/stations
```

Abra:

```text
https://www.radio.studiosatweb.com.br/listen-v2/
```

## 4. Rollback

O instalador imprime o backup Nginx criado em `/root/`.

A API V2 pode ser retirada sem afetar `/listen/`:

```bash
systemctl disable --now studiosat-api-v2.service
```


---

# Android

O aplicativo Android usa Media3/ExoPlayer diretamente.

## Reprodução

`PlaybackService` mantém um `MediaSession` e um `ExoPlayer`.

Para trocar de estação:

1. `stop()`
2. `clearMediaItems()`
3. `playbackParameters = 1.0`
4. `setMediaItem(HLS)`
5. `prepare()`
6. `play()`

Não há VU real, AudioEffect ou sampling.

## Background audio

O serviço é declarado como `mediaPlayback` e usa MediaSessionService.

## Próximas integrações

- dados de now-playing via API V2
- artwork
- Android Auto
- notificações customizadas

Essas integrações não devem mudar `PlaybackService` de forma que processe áudio.


---

# iOS

O aplicativo iOS usa AVPlayer diretamente.

## Áudio

`AVAudioSession` usa categoria `.playback`.

A troca de estação cria um novo `AVPlayerItem(url:)`.

A reprodução usa `playImmediately(atRate: 1.0)`.

## Background

`UIBackgroundModes` contém `audio`.

`MPRemoteCommandCenter` oferece play/pause, sem seek em rádio ao vivo.

## Princípio

Não adicionar `AVAudioEngine`, taps de áudio ou processing graph ao player.


---

# Plano de testes A/B

## Referências

A. HLS cru em player externo.
B. `/diag-bypass/`.
C. `/listen-v2/`.
D. Android V2.
E. iOS V2.

## Cenários

Para cada emissora:

1. tocar 10 minutos;
2. observar se existe aceleração;
3. observar se existe desaceleração;
4. observar mute espontâneo;
5. observar "áudio acumulado";
6. alternar Wi-Fi/4G no mobile;
7. bloquear/desbloquear tela;
8. trocar de estação 10 vezes;
9. pausar e retomar;
10. manter background por 30 minutos.

## Critério de aceite

O V2 deve preservar pitch/velocidade e não apresentar burst de áudio acumulado.

Qualidade percebida deve ser comparada ao HLS cru, usando os mesmos fones/caixas.


---

# Migração do legado para V2

## Fase 1

Publicar `/listen-v2/` sem tocar em `/listen/`.

## Fase 2

Testar áudio em Chrome, Edge, Firefox, Safari, Android e iOS.

## Fase 3

Gerar Android/iOS V2 e distribuir internamente.

## Fase 4

Quando V2 estiver aprovado, alterar a navegação principal para apontar a V2.

## Fase 5

Somente depois remover o código legado.

Nenhuma fase altera os endpoints HLS públicos.


---

# Operações

## API

```bash
systemctl status studiosat-api-v2
journalctl -u studiosat-api-v2 -f
curl http://127.0.0.1:9080/api/v2/health
```

## Dados

Arquivos editáveis:

```text
/etc/studiosat-v2/data/stations.json
/etc/studiosat-v2/data/now-playing/*.json
/etc/studiosat-v2/data/schedule/*.json
/etc/studiosat-v2/data/news.json
/etc/studiosat-v2/data/promotions.json
```

A API lê os arquivos em cada requisição nesta versão inicial.

## Portal

Arquivos publicados:

```text
/var/www/studiosat-v2/listen/
```

Não existe service worker no V2 inicial.


---

# Segurança

## Princípios

- API escuta somente em `127.0.0.1:9080`.
- Nginx é o único ponto público da API.
- Nenhum segredo é embutido no WebAssembly.
- O portal não recebe acesso de escrita aos arquivos de dados.
- A reprodução usa HTTPS.
- O V2 não requer permissão de microfone.

## CORS

A primeira versão permite leitura pública da API. Antes de adicionar endpoints
de escrita, autenticação e CORS restritivo devem ser implementados.
