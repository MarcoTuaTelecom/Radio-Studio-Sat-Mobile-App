# Integração do download no portal das rádios

O portal pode exibir um bloco “Baixe o aplicativo” quando os links oficiais estiverem ativos.

## Android

URL pública prevista após publicação:

`https://play.google.com/store/apps/details?id=br.com.studiosatweb.radio`

Para uma instalação direta controlada, publique o APK de `eas build --profile preview` no próprio portal/CDN, por exemplo em `/downloads/radio-studio-sat/RadioStudioSat-v1.0.0.apk`. Mantenha o repositório do código privado; um Release de repositório privado não é adequado como link público para ouvintes.

## iPhone

A Apple atribui um ID numérico ao registro do app no App Store Connect. Depois de criado, substitua:

`https://apps.apple.com/br/app/radio-studio-sat/idSEU_ID_APPLE`

## HTML sugerido para o portal

```html
<section id="app-studio-sat" class="section app-download">
  <div class="section-head"><h2>Radio Studio Sat no seu celular</h2></div>
  <p>As cinco emissoras em um único aplicativo, com música ao vivo, VU, tradução e conteúdo visual.</p>
  <div class="app-actions">
    <a class="app-store-btn" href="https://play.google.com/store/apps/details?id=br.com.studiosatweb.radio" rel="noopener">Google Play</a>
    <a class="app-store-btn" href="APPLE_STORE_URL_AQUI" rel="noopener">App Store</a>
    <a class="app-store-btn" href="/downloads/radio-studio-sat/RadioStudioSat-v1.0.0.apk">APK Android</a>
  </div>
</section>
```

Não publicar o link Apple com placeholder. Aplique esta integração ao portal somente depois que a ficha do aplicativo existir no App Store Connect.
