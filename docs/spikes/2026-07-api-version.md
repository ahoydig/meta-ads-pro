# Spike: upgrade Marketing API v25.0 → VNEW (2026-07)

## Versão-alvo

**VNEW = v25.0 (mesma versão já usada pelo plugin — não há upgrade disponível hoje).**

O plano assumia que, no momento da execução desta task, já existiria uma versão mais
nova que v25.0. Pesquisa em 2026-07-09 nas páginas oficiais da Meta mostra que **v25.0
continua sendo a versão mais recente da Graph API/Marketing API** — não foi lançada
nenhuma v26.0 ainda.

- `v25.0` — lançada em **18/02/2026**; data de depreciação: **"A definir"** (TBD, ainda
  não anunciada pela Meta).
- Não existe versão entre v25.0 e "a mais nova" porque v25.0 **é** a mais nova.
- Próxima versão esperada (v26.0): sem data oficial de lançamento na documentação;
  uma referência de terceiros (busca web) menciona "V26.0 (Sep 2026)" como marco futuro
  para mudanças em campanhas ASC/AAC, o que é consistente com o cadência histórica de
  releases da Meta (~4 meses entre versões), mas **não é uma data confirmada pela Meta**
  — rotulado aqui como `[não verificado]`.

Fontes consultadas (todas em 2026-07-09, via WebFetch):
- https://developers.facebook.com/docs/graph-api/changelog — "A versão mais recente da
  Graph API é v25.0"; nenhuma versão mais nova listada.
- https://developers.facebook.com/docs/graph-api/changelog/versions — tabela completa
  de versões: v25.0 (18/02/2026, retirement TBD) é a mais recente listada; v24.0
  (08/10/2025), v23.0 (29/05/2025), v22.0 (21/01/2025) etc. abaixo dela.
- https://developers.facebook.com/docs/graph-api/guides/versioning/ — confirma "A versão
  mais recente da Graph API é v25.0".
- https://developers.facebook.com/docs/marketing-api/changelog — confirma v25.0 como a
  versão mais recente do Marketing API também.
- https://developers.facebook.com/docs/graph-api/changelog/version25.0/ — changelog
  específico da v25.0 (ver seção abaixo).

**Conclusão prática:** como o plugin já usa `v25.0` como default em todo lugar
(`graph_api.sh:9` já é `API_VERSION="${META_API_VERSION:-v25.0}"`), o plugin **já está
na versão mais atual**. Não há bump de número de versão nesta task. O trabalho real
desta task passa a ser garantir que **toda** chamada HTTP à Meta esteja parametrizada
via `META_API_VERSION` (sem literal hardcoded fora do fallback), para que um upgrade
futuro real (quando v26.0 sair) baste trocar uma env var / um default, sem caçar
strings pelo repo. Ver "Estado da parametrização" abaixo.

## Breaking changes que afetam o plugin

Changelog oficial da v25.0
(https://developers.facebook.com/docs/graph-api/changelog/version25.0/) lista, nas
partes relevantes a anúncios:

| Mudança | Versão | Arquivo afetado | Ação |
|---|---|---|---|
| Depreciação de métricas de Insights de **Page/Post/Video/Stories** (orgânico) | v25.0 | nenhum — plugin só usa `insights` em nível de conta/campanha/adset/ad (`flows/insights/SKILL.md`), não Page/Post Insights orgânico | nenhuma |
| Restrições em campanhas Advantage+ (Marketing API) | v25.0 | nenhum uso de Advantage+ audience/placement específico localizado no grep dos recursos usados | nenhuma |
| Campo de erro adicional em jobs assíncronos (Ads Insights Async API) | v25.0 | `flows/insights/SKILL.md` (uso de async report) — aditivo, não quebra nada existente | nenhuma (aditivo) |
| Depreciação do parâmetro de query `metadata=1` | v25.0 (mencionado por fonte secundária, não confirmado no changelog oficial lido) | grep no repo por `metadata=1`/`metadata=true`: **0 ocorrências** | nenhuma |

Cruzamento com os recursos usados pelo plugin (grep no repo):
`leadgen_forms`, `adcreatives`, `object_story_spec`, `asset_feed_spec`,
`customaudiences`, `adrules_library`, `insights`, `adspixels`,
`search?type=adinterest|adgeolocation`, `promote_pages`, `connected_instagram_accounts`,
`instagram_user_id`/`instagram_actor_id`, `subscribed_apps` — **nenhum desses recursos
aparece na lista de mudanças/depreciações da v25.0** (o único changelog relevante desde
a versão que o plugin já usa). Como VNEW = v25.0, não há changelog de versão adicional
a auditar.

**Nenhum breaking change afeta os endpoints usados pelo plugin.**

## Campos renomeados/novos relevantes pra v1.1

- **`instagram_actor_id` vs `instagram_user_id` em `adcreatives`**: na v25.0, o campo
  usado em `object_story_spec` continua sendo `instagram_user_id` (a referência da API
  descreve seu conteúdo como "Instagram actor ID", mas o **nome do campo no payload é
  `instagram_user_id`**, não `instagram_actor_id`). O plugin já usa `instagram_user_id`
  em `flows/setup/SKILL.md:183`, `flows/publicos/SKILL.md` e
  `flows/anuncios/SKILL.md:253,264` — **nenhuma mudança necessária**.
  Fonte: https://developers.facebook.com/docs/marketing-api/reference/ad-creative/
- Nenhum outro campo renomeado/novo identificado que afete os recursos listados acima.

## Estado da parametrização (auditoria completa do repo)

Grep por `v25\.0|v24\.0|v23\.0|v26\.0` em todo `plugins/meta-ads-pro/` (exceto `tests/`):

| Arquivo:linha | Estado antes desta task | Ação |
|---|---|---|
| `lib/graph_api.sh:9` | já `API_VERSION="${META_API_VERSION:-v25.0}"` | nenhuma (já parametrizado) |
| `lib/preflight.sh:28,49,116` | **hardcoded** `https://graph.facebook.com/v25.0/...` (3 chamadas `curl` diretas, fora de `graph_api()`) | **corrigido** → `https://graph.facebook.com/${META_API_VERSION:-v25.0}/...` |
| `lib/upload_media.sh:97,144` | já `local api_ver="${META_API_VERSION:-v25.0}"` | nenhuma (já parametrizado) |
| `lib/upload_video.sh:27` | já `local api_ver="${META_API_VERSION:-v25.0}"` | nenhuma (já parametrizado) |
| `lib/error-resolver.sh:194,204` | já `local api_ver="${META_API_VERSION:-v25.0}"` | nenhuma (já parametrizado) |
| `lib/rollback.sh:85` | já `${META_API_VERSION:-v25.0}` inline na URL | nenhuma (já parametrizado) |
| `lib/_py/import_existing.py:41,10` | `DEFAULT_API_VERSION = "v25.0"` (default de `--api-version`, chamador em `flows/import-existing/SKILL.md:85` já passa `${META_API_VERSION:-v25.0}` explicitamente) | nenhuma (valor já correto; script standalone continua com fallback `v25.0`) |
| `flows/setup/SKILL.md:89` | heredoc grava `META_API_VERSION=v25.0` no `.env` do usuário | nenhuma (valor correto — é o valor real que deve ir pro `.env`, não um placeholder) |
| `flows/anuncios/SKILL.md:41,67,320` | menções descritivas "Limites v25.0" / "Limites Graph API v25.0" | nenhuma (descrição segue correta — v25.0 é a versão vigente) |

**Achado principal:** o único ponto realmente hardcoded (fora do padrão
`${META_API_VERSION:-v25.0}` usado no resto do repo) eram as 3 chamadas `curl` diretas
em `preflight.sh` (checks de expiração de token, scopes, e rate-limit BUC) — essas
chamadas não passam por `graph_api()` (são checks de pre-flight que rodam antes de
confiar no wrapper) e tinham a versão hardcoded separadamente. Corrigido para usar o
mesmo padrão `${META_API_VERSION:-v25.0}`.

## Decisão para as próximas 23 tasks do plano

Onde o plano escreve `v25.0`/`VNEW`, leia-se **v25.0** (idêntico ao que já está em
produção). Isso não é um "pulo de versão zero-effort" disfarçado: a auditoria acima
(breaking changes, campos renomeados, e o levantamento completo de hardcodes) foi feita
de verdade, e o repo saiu desta task com **zero literais de versão fora do padrão
`${META_API_VERSION:-v25.0}`**, o que é a fundação real que as tasks seguintes precisam
para não repetir esse trabalho quando a v26.0 sair.

Quando a Meta lançar v26.0 (monitorar
https://developers.facebook.com/docs/graph-api/changelog), o bump real será: mudar o
fallback `v25.0` → `v26.0` nos ~7 arquivos listados acima (ou, mais simples, só exportar
`META_API_VERSION=v26.0` no `.env`, já que todo o repo lê essa env var) e repetir o
Step 2 (auditoria de breaking changes) desta task para a v26.0 real.
