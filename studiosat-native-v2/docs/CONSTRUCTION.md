# Diário de construção

## 0.1.0

### Criado do zero

- workspace Rust novo
- core de modelos
- API Axum V2
- portal Rust/WASM
- media bridge HLS limpa
- aplicativo Android Media3
- aplicativo iOS AVPlayer
- deploy paralelo `/listen-v2/`
- documentação de arquitetura/build/deploy/teste

### Deliberadamente não copiado

- App.tsx legado
- Expo Audio
- useAudioSampleListener
- WebAudio/AudioContext
- service worker legado
- lógica de perseguição de live edge
- player HTML legado


## Publicação inicial no GitHub — 22/09/2026

- branch de desenvolvimento: `feature/studiosat-native-v2`
- fonte expandida e validada dentro de `studiosat-native-v2/`
- contrato de dados validado com `DATA_CONTRACT=OK`
- caminho de mídia validado com `CLEAN_MEDIA_PATH=OK`
- workflow executável: `.github/workflows/studiosat-native-v2-ci.yml`
- o sistema legado permanece intacto durante a validação A/B
