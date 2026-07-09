---
name: meta-ads-news
description: "Checagem sob demanda do changelog oficial da Marketing/Graph API contra a versão usada pelo plugin. Reporta breaking changes, deprecações com data e features novas relevantes pro funil de leads. Sem infra — roda via WebFetch, sem chamada à Graph API."
---

# meta-ads-news

Checagem sob demanda: "o que mudou na API da Meta e o que isso afeta neste plugin". Não roda em cron nem em background — só quando o usuário pedir (`/meta-ads-news`). Não faz nenhuma chamada à Graph API; só lê o changelog público via WebFetch e cruza com a superfície de endpoints que o plugin usa.

## Quando usar

- Antes de fazer upgrade de `META_API_VERSION`
- Quando a Meta anunciar deprecação por e-mail/aviso e quiser saber se afeta o plugin
- Revisão periódica (ex: trimestral) pra não ser pego de surpresa por breaking change

## Passo 1 — Versão em uso

```bash
grep -m1 '^META_API_VERSION=' .env 2>/dev/null || true
```

Se não achar no `.env` do projeto, o fallback é o default hardcoded em `lib/graph_api.sh:9` (`API_VERSION="${META_API_VERSION:-v25.0}"`). Essa é a versão de referência (`vX`) do restante do fluxo.

## Passo 2 — Buscar o changelog oficial

WebFetch nesta ordem:

1. `https://developers.facebook.com/docs/graph-api/changelog` — índice geral (mostra qual é a versão mais recente e a janela de versões suportadas).
2. `https://developers.facebook.com/docs/graph-api/changelog/version{X}` — página específica da versão em uso (`vX`), e o mesmo padrão para cada versão entre `vX` e a mais recente (`vY`), se houver mais de uma. **É aqui que aparecem os breaking changes/deprecações reais** — o índice geral costuma ser só um hub de navegação sem o detalhe.
3. Se a página de Graph API não cobrir algo específico de anúncios/Marketing API, complementar com `https://developers.facebook.com/docs/marketing-api/changelog`.

Se o WebFetch falhar (timeout, 404, bloqueio) em qualquer uma dessas: **reportar a falha explicitamente e parar** — não seguir pros próximos passos com dado incompleto, e não inventar conteúdo de changelog que não foi lido.

## Passo 3 — Cruzar com a superfície do plugin

Superfície real de endpoints/campos que o plugin toca hoje (pós-v1.1) — **manter esta lista viva: todo novo flow que adicionar um recurso novo da Graph/Marketing API deve entrar aqui**:

| Recurso | Onde é usado | Observação |
|---|---|---|
| `leadgen_forms` | `flows/lead-forms/` | CRUD de formulário de lead |
| `test_leads` | `flows/lead-forms/` | Gera lead de teste sem gasto real |
| `tracking_parameters` | `flows/lead-forms/` | Condicionais/thank-you CTA no formulário |
| `adcreatives` (`object_story_spec`, `asset_feed_spec`) | `flows/anuncios/` | Criativo normal e dinâmico |
| `source_instagram_media_id` | `flows/boost/` | Boost de post/Reel próprio do IG (sem dark post) |
| `image_crops`, `asset_customization_rules` | `flows/anuncios/` | Crop 1:1 explícito e imagem por placement |
| `child_attachments` | `flows/anuncios/` | Modo carrossel (2–10 cartões) |
| `generatepreviews`, `{creative_id}/previews` | `flows/anuncios/`, `flows/boost/` | Preview oficial da Meta (iframe) |
| `{ig_user}/media` (com `boost_eligibility_info`) | `flows/boost/` | Checagem preditiva de elegibilidade de boost antes de tentar |
| `customaudiences` | `flows/publicos/` | Custom audiences, lookalikes, website/pixel audiences |
| `saved_audiences` | `flows/publicos/` | **Somente leitura** — `POST` bloqueado por capability do app; guard-rail testado ao vivo (`tests/09-publicos.sh`, test_03) |
| `adspixels`, `{pixel_id}/events` | `flows/publicos/`, `flows/crm/` | Pixel + CAPI (server-side events) |
| `adrules_library` | `flows/regras/` | Regras automáticas de otimização |
| `insights` (conta/campanha/conjunto/anúncio + async) | `flows/insights/` | Relatórios de performance |
| `search` (`adinterest`, `adgeolocation`) | `flows/conjuntos/` | Segmentação por interesse/localização |
| `subscribed_apps` | webhook de leadgen | Subscrição da página pro recebimento de eventos |

Pra cada versão entre `vX` e `vY`, ler o que a Meta anunciou e checar se algum item bate com esta tabela.

## Passo 4 — Relatório PT-BR

Formato (ilustrativo — os valores reais vêm do WebFetch, nunca inventados):

```
┌ Versão do plugin: v<X> · Mais recente: v<Y> · Depreciação de v<X>: <data ou "sem data anunciada">
├ 🔴 Breaking (afeta flow <nome>): <descrição>          → <ação sugerida>
├ 🟡 Deprecação futura (<data>): <descrição>            → <o que fazer até lá>
└ 🟢 Novidade aproveitável: <descrição>                 → <ideia de uso no funil de leads>
```

Regras de montagem:

- **Um bloco por item real** encontrado na página. Se não houver breaking/deprecação/novidade em alguma categoria, omitir a linha — não preencher com "nenhum" artificialmente linha por linha.
- Se **nada** do changelog afeta a superfície do Passo 3, dizer isso de forma explícita e direta (ex: "nenhum item do changelog de v{X}→v{Y} afeta os flows atuais do plugin") — **zero alarme falso**.
- **NUNCA inventar item de changelog.** Só reportar o que a página buscada efetivamente diz. Se o item existir na página mas não tocar nenhum recurso da tabela do Passo 3, classificar como watch-item de baixo risco (🟡) em vez de ignorar silenciosamente — mas deixar claro que hoje não afeta.
- Se o WebFetch falhar (Passo 2), o relatório é só isso: qual URL falhou e por quê. Parar aí.

## Referência rápida

- Fonte de verdade da versão em uso: `.env` (`META_API_VERSION`) > default em `lib/graph_api.sh:9`.
- Este flow não escreve em nenhum arquivo do projeto e não faz `POST`/`GET` na Graph API — 100% leitura de doc pública via WebFetch.
- Não existe suíte de teste bash pra este flow (não há chamada à Graph API pra testar) — a validação é rodar `/meta-ads-news` de verdade e conferir que o relatório cita a versão real e itens verificáveis na página.
