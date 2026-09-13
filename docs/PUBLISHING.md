# Publicação — Android e iPhone

## Identidade do aplicativo

- Nome: `Radio Studio Sat`
- Android package: `br.com.studiosatweb.radio`
- iOS bundle identifier: `br.com.studiosatweb.radio`
- Versão inicial: `1.0.0`

Não altere os identificadores depois de publicar a primeira versão.

## 1. Preparação local

Requisitos:

- Node.js compatível com Expo SDK 57
- conta Expo/EAS
- Android Studio para testes locais Android (opcional se usar EAS Build)
- Xcode/macOS para builds locais iOS (opcional se usar EAS Build)

Comandos:

```bash
npm install
npx expo install --fix
npx expo-doctor
npm run typecheck
npx eas-cli@latest login
npx eas-cli@latest init
```

Depois de `eas init`, substitua `REPLACE_AFTER_EAS_INIT` em `app.json` pelo `projectId` criado.

## 2. Build Android

### APK de teste para o portal/equipe

```bash
npx eas-cli@latest build --platform android --profile preview
```

O perfil `preview` gera APK instalável diretamente.

### AAB para Google Play

```bash
npx eas-cli@latest build --platform android --profile production
```

Baixe o `.aab` gerado e envie ao Play Console.

## 3. Google Play

Em setembro de 2026, novos apps e atualizações precisam mirar Android 16 / API 36. O Expo SDK 57 usado neste projeto já usa `targetSdkVersion 36`.

1. Crie/acesse a conta de desenvolvedor no Google Play Console.
2. `Todos os apps` → `Criar app`.
3. Nome: **Radio Studio Sat**; idioma principal: Português (Brasil).
4. Configure a ficha: descrição curta, descrição completa, ícone 512x512, feature graphic e screenshots.
5. Preencha `Conteúdo do app`: política de privacidade, classificação indicativa, público-alvo, anúncios (se houver) e segurança dos dados.
6. Use primeiro `Teste interno` ou `Teste fechado`.
7. Crie uma versão e envie o `.aab` de produção.
8. Resolva todos os avisos do painel e envie para revisão.
9. Após aprovação, publique em Produção.

## 4. Build iOS

```bash
npx eas-cli@latest build --platform ios --profile production
```

Na primeira vez, o EAS orientará a criação/uso dos certificados e provisioning profiles da conta Apple Developer.

## 5. App Store

Desde 28 de abril de 2026, uploads ao App Store Connect precisam ser construídos com o SDK do iOS 26 ou superior. O Expo SDK 57 é compatível com a geração atual necessária para esta submissão.

1. Tenha uma assinatura ativa do Apple Developer Program.
2. Em App Store Connect → Apps → `+` → `New App`.
3. Nome: **Radio Studio Sat**.
4. Bundle ID: `br.com.studiosatweb.radio`.
5. SKU sugerido: `studiosat-radio-ios-001`.
6. Cadastre descrição, palavras-chave, categoria `Music`, URL de suporte, política de privacidade e screenshots.
7. Envie o build com EAS Submit ou Transporter.
8. Associe o build à versão 1.0.0.
9. Preencha App Privacy e classificação etária.
10. `Add for Review` → `Submit for Review`.

## 6. Envio automatizado pelo EAS

Após as credenciais das lojas estarem configuradas:

```bash
npm run submit:android
npm run submit:ios
```

## 7. Portal das rádios

Depois que as lojas fornecerem os URLs oficiais, use:

- `https://play.google.com/store/apps/details?id=br.com.studiosatweb.radio`
- URL final do App Store Connect/App Store para o app iOS

Para download direto Android, publique também o APK do perfil `preview` no próprio portal/CDN. Se o repositório de código permanecer privado, não use um asset de GitHub Release como link público, pois o visitante precisará estar autenticado. Para o público geral, priorize Google Play e App Store; o APK direto é uma alternativa controlada.
