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

## Apêndice — Task 15: `image_crops` + `asset_customization_rules` (2026-07-09)

Testes live contra a conta real (`tests/20-criativo-avancado.sh`,
`test_02_image_crops` e `test_03_asset_customization_rules`), padrão da casa:
payload → resposta verbatim (nenhum é hipotético), `META_API_VERSION` = v25.0.

### `image_crops` — divergência achada ao vivo

O brief da task assumia `image_crops` como campo **top-level** do creative (ao lado
de `object_story_spec`, `name` etc.). Testado ao vivo, isso **não funciona**: a Meta
aceita o POST (retorna `201` com `id`), mas ignora o campo em silêncio — nenhum erro,
o GET seguinte simplesmente não devolve `image_crops`.

**Tentativa 1 — `image_crops` top-level (payload do brief, sem correção):**

```json
{
  "name": "TEST_crops_debug",
  "object_story_spec": {
    "page_id": "108356564252733",
    "link_data": {
      "message": "crop test debug",
      "link": "https://ahoy.digital",
      "image_hash": "c12e54946ffb81e3652ad929fa3c325e"
    }
  },
  "image_crops": {"100x100": [[0, 420], [1080, 1500]]}
}
```

Resposta do `POST .../adcreatives` (sucesso, sem erro — é isso que engana):

```json
{"id": "996708006500853"}
```

Resposta do `GET {id}?fields=image_crops` logo em seguida:

```json
{"id": "996708006500853"}
```

`image_crops` some — a Meta aceitou o creative e descartou o campo em silêncio.

**Tentativa 2 — `image_crops` aninhado em `object_story_spec.link_data` (shape
correto, confirmado pela doc oficial
[ads-commerce/marketing-api/image-crops](https://developers.facebook.com/documentation/ads-commerce/marketing-api/image-crops)):**

```json
{
  "name": "TEST_crops_debug2",
  "object_story_spec": {
    "page_id": "108356564252733",
    "link_data": {
      "message": "crop test debug2",
      "link": "https://ahoy.digital",
      "image_hash": "c12e54946ffb81e3652ad929fa3c325e",
      "image_crops": {"100x100": [[0, 420], [1080, 1500]]}
    }
  }
}
```

Resposta do `POST`:

```json
{"id": "2074362566500876"}
```

Resposta do `GET {id}?fields=image_crops` (persistiu, e também espelha no campo
top-level read-only):

```json
{"image_crops": {"100x100": [[0, 420], [1080, 1500]]}, "id": "2074362566500876"}
```

**Conclusão:** `image_crops` só persiste dentro de
`object_story_spec.link_data.image_crops`. O campo `image_crops` top-level do
`AdCreative` existe no schema de leitura (`GET .../adcreatives?fields=image_crops`
é um field válido, é assim que o teste confirma persistência), mas **não é onde se
escreve** — escrever lá é aceito e descartado sem erro, o tipo de bug silencioso mais
perigoso de reproduzir sem teste live. `SKILL.md` (Passo 5) e `tests/20-criativo-avancado.sh`
(`test_02_image_crops`) corrigidos pro shape aninhado.

A chave `"100x100"` (aspect ratio 1:1) foi testada ao vivo e funciona. Não foi
verificada nenhuma outra chave (`[não verificado]`) — a doc oficial confirma que "a
chave descreve um aspect ratio" mas não lista o enum completo nesta versão da página;
uma chave legada (`"191x100"`, 1.91:1) aparece em fontes de terceiros como **depreciada**
nas versões mais novas da API em favor de `use_flexible_image_aspect_ratio`, mas isso
não foi confirmado na doc oficial da Meta nem testado nesta task — tratar como
`[não verificado — fonte secundária]` até um spike dedicado.

### `asset_customization_rules` — sem divergência

O payload do brief (`asset_feed_spec.images[].adlabels` + `asset_customization_rules`
com `customization_spec.{publisher_platforms,facebook_positions,instagram_positions}`
+ `image_label.name`) foi aceito **verbatim**, sem nenhuma correção de sintaxe.

Payload enviado (`test_03_asset_customization_rules`):

```json
{
  "name": "TEST_asset_custom_debug",
  "object_story_spec": {"page_id": "108356564252733"},
  "asset_feed_spec": {
    "images": [
      {"hash": "a4373875f17ade6d28d5623ef146c7cc", "adlabels": [{"name": "img_feed"}]},
      {"hash": "c12e54946ffb81e3652ad929fa3c325e", "adlabels": [{"name": "img_story"}]}
    ],
    "bodies": [{"text": "corpo"}],
    "titles": [{"text": "titulo"}],
    "link_urls": [{"website_url": "https://ahoy.digital"}],
    "call_to_action_types": ["LEARN_MORE"],
    "ad_formats": ["SINGLE_IMAGE"],
    "asset_customization_rules": [
      {
        "customization_spec": {
          "publisher_platforms": ["facebook", "instagram"],
          "facebook_positions": ["feed"],
          "instagram_positions": ["stream"]
        },
        "image_label": {"name": "img_feed"}
      },
      {
        "customization_spec": {
          "publisher_platforms": ["facebook", "instagram"],
          "facebook_positions": ["story"],
          "instagram_positions": ["story"]
        },
        "image_label": {"name": "img_story"}
      }
    ]
  }
}
```

Resposta do `GET {id}?fields=asset_feed_spec` (creative `1318626883330212`,
deletado no cleanup do teste):

```json
{
  "asset_feed_spec": {
    "images": [
      {"adlabels": [{"name": "img_feed", "id": "120255177459050196"}], "hash": "a4373875f17ade6d28d5623ef146c7cc"},
      {"adlabels": [{"name": "img_story", "id": "120255177459060196"}], "hash": "c12e54946ffb81e3652ad929fa3c325e"}
    ],
    "bodies": [{"text": "corpo"}],
    "call_to_action_types": ["LEARN_MORE"],
    "descriptions": [{"text": "Marketing, IA e automação a serviço de negócios reais."}],
    "link_urls": [{"website_url": "https://ahoy.digital/"}],
    "titles": [{"text": "titulo"}],
    "ad_formats": ["SINGLE_IMAGE"],
    "asset_customization_rules": [
      {
        "customization_spec": {"age_max": 65, "age_min": 13, "publisher_platforms": ["facebook", "instagram"], "facebook_positions": ["feed"], "instagram_positions": ["stream"]},
        "image_label": {"name": "img_feed", "id": "120255177459050196"},
        "priority": 1
      },
      {
        "customization_spec": {"age_max": 65, "age_min": 13, "publisher_platforms": ["facebook", "instagram"], "facebook_positions": ["story"], "instagram_positions": ["story"]},
        "image_label": {"name": "img_story", "id": "120255177459060196"},
        "priority": 2
      }
    ]
  },
  "id": "1318626883330212"
}
```

A Meta enriquece a resposta com `age_min`/`age_max` por rule, `priority` incremental
e (no nível do `asset_feed_spec`) `optimization_type: "PLACEMENT"` — nenhum desses
campos foi enviado no payload; são defaults auto-preenchidos, não obrigatórios na
escrita.

**Nota sobre `descriptions`:** a resposta trouxe um `descriptions[]` que não foi
enviado no payload — provável default herdado da conta/Página (não investigado nesta
task, fora de escopo; não afeta o resultado do teste, que valida só a persistência de
`asset_customization_rules`).

## Addendum (Task 18, 2026-07-09) — `saved_audiences` POST bloqueado por capability do app

Durante a Task 18 (escrita de saved audiences via API), `POST act_{id}/saved_audiences`
foi testado ao vivo na conta de teste (`AD_ACCOUNT_ID=act_763408067802379`) com
`GRAPH_API_SKIP_RESOLVER=1` (pra descartar interferência do error-resolver) e retornou:

```json
{"error":{"message":"(#3) Application does not have the capability to make this API call.","type":"OAuthException","code":3,"fbtrace_id":"AWHZlSDOOfLEIw5ZzCJmhlF"}}
```

HTTP 400, `OAuthException` código `3`. **Não é** um breaking change de versão — não
consta em nenhum changelog auditado acima, e o mesmo app/token escreve normalmente em
`customaudiences`, `campaigns`, `adsets` e `leadgen_forms` (endpoints já cobertos pela
auditoria de superfície desta task). É um gate de **capability/permissão do app**
específico do endpoint `saved_audiences` — normalmente liberado via App Review
adicional na Meta, fora do controle deste plugin ou desta task.

**Decisão:** `flows/publicos/SKILL.md` seção 2.6 documenta o estado como "somente
leitura + criação guiada no Ads Manager" (não força a escrita). Teste de regressão em
`tests/09-publicos.sh::test_03_saved_audience_create_guardrail` — guard-rail que
**PASSA** enquanto a API continuar rejeitando com esse erro exato e **FALHA** se a
API um dia aceitar (ou rejeitar com um erro diferente), sinalizando a necessidade de
reavaliar. Ver relatório completo em `.superpowers/sdd/task-18-report.md`.
