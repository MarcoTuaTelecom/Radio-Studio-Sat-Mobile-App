# Página pública “Baixar App” — Radio Studio Sat

O repositório inclui uma página estática, responsiva e independente em `web/download/index.html` e o instalador `scripts/deploy-download-page.sh`.

## URL pública prevista

`https://www.radio.studiosatweb.com.br/app/`

O portal Studio Sat já usa `/var/www/studiosat-radio-portal` como document root. O instalador cria apenas o subdiretório `app/`; não modifica a home e não precisa editar a configuração NGINX atual.

## Instalação inicial — sem APK/lojas ainda

```bash
cd /root/Radio-Studio-Sat-Mobile-App
git pull --ff-only
sudo VERSION=1.0.0 bash scripts/deploy-download-page.sh
```

A página será publicada com os botões ainda indisponíveis para os artefatos que não existirem.

## Publicar também um APK de teste ou produção

```bash
sudo VERSION=1.0.0 \
  APK_SOURCE=/caminho/RadioStudioSat-v1.0.0.apk \
  bash scripts/deploy-download-page.sh
```

O script copia o APK para:

- `/var/www/studiosat-radio-portal/downloads/apps/RadioStudioSat-v1.0.0.apk`
- `/var/www/studiosat-radio-portal/downloads/apps/RadioStudioSat-latest.apk`

## Quando Google Play e App Store estiverem públicas

```bash
sudo VERSION=1.0.0 \
  APK_SOURCE=/caminho/RadioStudioSat-v1.0.0.apk \
  PLAY_STORE_URL='https://play.google.com/store/apps/details?id=br.com.studiosatweb.radio' \
  APP_STORE_URL='https://apps.apple.com/br/app/SEU-ID-APPLE' \
  bash scripts/deploy-download-page.sh
```

Não invente o ID Apple. Preencha `APP_STORE_URL` somente depois que o App Store Connect fornecer a URL oficial.

## Segurança operacional

O script exige `root`, valida a existência do portal e do `index.html`, cria backup antes de alterar `app/`, valida o HTML renderizado, gera SHA-256 e executa `nginx -t` se NGINX estiver instalado. Se ocorrer erro depois da primeira alteração, o `trap` tenta restaurar a página anterior automaticamente.

Os backups ficam em `/var/backups/studiosat/app-download/<UTC>/`.

## Remover a página

```bash
sudo rm -rf /var/www/studiosat-radio-portal/app
```

Isso não afeta o player nem as cinco URLs HLS.
