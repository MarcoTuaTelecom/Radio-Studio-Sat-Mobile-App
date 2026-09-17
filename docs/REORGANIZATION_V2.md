# Mobile — Plano de reorganização v2

## Problemas observados na auditoria de 2026-09-17

1. O repositório mistura aplicativo com recuperação/forense de NS1.
2. `scripts/build-release.sh` conhece e pode publicar diretamente no diretório do portal.
3. `scripts/ns1-all-in-one.sh` usa o repositório Mobile para validar Nginx, Portal, CMS e os cinco HLS.
4. URLs de runtime aparecem em mais de uma camada (`app.json`, `stations.ts`, `api.ts`).
5. Não há lockfile versionado no baseline auditado; o CI usa `npm install`.
6. `App.tsx` concentra muita lógica de player, metadata, UI e estado.
7. `web/pwa` e `web/download` são superfícies web e devem ser avaliadas para o repositório Portal.

## Alvo

### Manter

```text
App.tsx
src/
assets/
app.json
eas.json
package.json
tsconfig.json
.github/workflows/
docs/
scripts/
  app-build/
  app-release/
  assets/
```

### Migrar para Core/OPS

Scripts de NS1/recovery/Nginx/HLS/portal-operacional.

### Avaliar migração para Portal

```text
web/pwa/
web/download/
```

## Sequência recomendada

1. Não apagar nada no primeiro PR.
2. Copiar operações para Core e preservar histórico Git.
3. Validar scripts copiados.
4. Separar `build app` de `publish download page`.
5. Gerar lockfile com a versão de Node suportada e validar Expo Doctor.
6. Trocar CI de `npm install` para `npm ci` somente depois do lockfile.
7. Criar `src/config/runtime.ts` para base URLs.
8. Refatorar `App.tsx` sem alterar UX inicialmente.

## Critério de sucesso

Um clone limpo deste repositório deve conseguir:

- instalar dependências;
- executar typecheck;
- validar Expo;
- gerar assets;
- construir Android/iOS;

sem exigir acesso root, Nginx, MediaMTX, `/var/www` ou credenciais do servidor de produção.
