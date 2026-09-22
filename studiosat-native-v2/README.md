# Studio Sat Native V2

Nova plataforma de reprodução da Studio Sat Web, construída do zero e isolada do
portal/aplicativo legado.

## Objetivo

O princípio central deste projeto é simples:

> O caminho de mídia não deve ser usado por componentes visuais, VU meters,
> analisadores, DSPs ou rotinas de sincronização próprias da aplicação.

A origem entrega HLS. O cliente entrega esse HLS ao mecanismo de mídia da
plataforma:

- Web: `<audio>` nativo; HLS.js somente quando o navegador não possui HLS nativo.
- Android: AndroidX Media3 / ExoPlayer.
- iOS: AVPlayer / AVFoundation.
- API e regras de negócio: Rust + Axum.
- Portal: Rust compilado para WebAssembly.

## Estrutura

```text
studiosat-native-v2/
├── rust/
│   ├── core/              # modelos compartilhados
│   └── api/               # API V2 em Rust/Axum
├── web/                   # portal Rust/WASM
├── android/               # app Android nativo Media3
├── ios/                   # app iOS nativo AVPlayer
├── data/                  # dados iniciais da API
├── deploy/                # systemd / nginx / implantação
├── scripts/               # build, validação e pacote
└── docs/                  # documentação técnica completa
```

## URLs da primeira implantação

A primeira implantação é deliberadamente paralela:

- legado: `/listen/`
- V2: `/listen-v2/`
- API V2: `/api/v2/`

Nada substitui o sistema antigo até o teste A/B ser aprovado.

## Regra de áudio

Não são permitidos no caminho audível do V2:

- `AudioContext`
- `AnalyserNode`
- amostragem do áudio para VU
- alteração automática de `playbackRate`
- busca periódica em `currentTime`
- time stretching
- DSP no cliente
- transcodificação no portal/app

Consulte `docs/MEDIA_PIPELINE.md` e `docs/ADR-001-CLEAN-MEDIA-PATH.md`.

## Build rápido no NS1

```bash
cd studiosat-native-v2
bash scripts/bootstrap-linux.sh
bash scripts/build-linux.sh
sudo bash deploy/install-ns1.sh
```

Depois:

```text
https://www.radio.studiosatweb.com.br/listen-v2/
```

## Android

```bash
cd android
gradle :app:assembleDebug
```

Saída esperada:

```text
android/app/build/outputs/apk/debug/app-debug.apk
```

## iOS

No macOS:

```bash
brew install xcodegen
cd ios
xcodegen generate
open StudioSat.xcodeproj
```

## Estado

Versão inicial: `0.1.0`.

Esta versão prioriza a cadeia de reprodução limpa e testável. Integrações
editoriais avançadas podem evoluir sem alterar o player.

## Documentação

Consulte `docs/MASTER.md` e `docs/CONSTRUCTION.md`.
