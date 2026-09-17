# Radio Studio Sat Mobile — Escopo canônico do repositório

## Papel

Este repositório é a fonte canônica do aplicativo Radio Studio Sat para Android/iOS e do código cliente compartilhado do app.

## Pertence aqui

- Expo / React Native;
- `App.tsx` e `src/`;
- componentes, hooks, serviços e tipos do cliente;
- assets do aplicativo;
- `app.json`, `eas.json`, TypeScript;
- scripts de geração de assets do app;
- scripts de build/release EAS;
- documentação de publicação em lojas;
- testes/CI do aplicativo.

## Não pertence aqui

A responsabilidade canônica dos itens abaixo é do repositório Core/OPS `MarcoTuaTelecom/Projeto-StudioSat-Web-Radios-e-TVs-`:

- recuperação de NS1/NS2;
- alteração de Nginx/TLS;
- alteração de MediaMTX;
- recuperação de portal/CMS;
- health transversal de produção;
- RadioBOSS/mirror;
- scripts de TV;
- scripts que administram diretamente `/var/www/...`, `/etc/nginx/...` ou serviços de infraestrutura.

## Relação com o Portal

O aplicativo deve consumir contratos públicos, principalmente:

- `https://www.radio.studiosatweb.com.br/api/content`
- `https://radio.studiosatweb.com.br/<station-id>/index.m3u8`
- `https://radio.studiosatweb.com.br/assets/now/<station-id>.json`

O app não deve conhecer a persistência interna do CMS nem publicar diretamente arquivos do portal.

## Migração

A limpeza será progressiva e não destrutiva:

1. inventariar scripts existentes;
2. copiar scripts de infraestrutura para Core/OPS;
3. validar equivalência e rollback;
4. promover a cópia do Core como canônica;
5. remover a duplicata do Mobile somente em PR posterior.

## Fonte de contexto do projeto

O MASTER do projeto vive em:

`MarcoTuaTelecom/Projeto-StudioSat-Web-Radios-e-TVs-/project-context/00-MASTER.md`
