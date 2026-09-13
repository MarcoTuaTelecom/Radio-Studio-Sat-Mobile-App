# Radio Studio Sat — Android + iPhone

Aplicativo oficial das cinco emissoras Studio Sat em uma única experiência móvel, com interface clara e foco na emissora que está tocando.

## Emissoras

- Radio Studio Sat / Principal
- Radio Studio Sat Pop
- Radio Studio Sat Rock
- Radio Studio Sat Clássicas
- Radio Studio Sat Country

## O que já está implementado

- streaming HLS real das cinco rádios em `radio.studiosatweb.com.br`;
- troca de emissora pelos pequenos seletores no rodapé;
- player em primeiro plano e segundo plano;
- controles de lock screen/notification;
- artista, música, programa, locutor e capa por metadata JSON;
- VU real calculado a partir das amostras PCM da reprodução;
- box independente de vídeo/imagem para comercial, notícia e informação;
- vídeos do box sempre mudos para não interferirem no áudio da rádio;
- carrossel automático por emissora usando o CMS do portal;
- área de tradução/contexto fornecida pelo metadata;
- fallback resiliente quando metadata ou CMS estiverem indisponíveis;
- configuração EAS para APK de teste, Android App Bundle e iOS;
- CI com Expo Doctor + TypeScript.

## Infraestrutura usada

```text
Studio Sat App
  ├─ HLS: https://radio.studiosatweb.com.br/<station-id>/index.m3u8
  ├─ Now Playing: https://radio.studiosatweb.com.br/assets/now/<station-id>.json
  └─ Conteúdo/carrossel: https://www.radio.studiosatweb.com.br/api/content
```

O app não altera o playout existente e não contém credenciais.

## Desenvolvimento

```bash
npm install
npx expo install --fix
npx expo-doctor
npm run typecheck
npm start
```

Para testar background playback e lock-screen no Android/iPhone, use um development build ou build EAS; não trate Expo Go como validação final de produção.

## Publicação

Leia `docs/PUBLISHING.md`.

## Integração de conteúdo

Leia `docs/API_CONTRACT.md`.

## Estado de produção

O código está pronto para build, mas a publicação final depende das contas de desenvolvedor Google/Apple e de validar no servidor de produção se o endpoint de metadata `/assets/now/<station-id>.json` já está publicado para as cinco rádios. Se estiver ausente, o áudio funciona e a UI entra em fallback; o contrato necessário está documentado.

## Página pública de download

A página `web/download/index.html` e o instalador `scripts/deploy-download-page.sh` publicam o app em `https://www.radio.studiosatweb.com.br/app/` sem substituir a homepage do portal. O script aceita APK, URL Google Play e URL App Store por variáveis de ambiente, cria backup e valida o NGINX. Veja `docs/DOWNLOAD_PAGE_DEPLOY.md`.
