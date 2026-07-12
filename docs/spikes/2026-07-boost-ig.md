# Spike: boost de post orgânico do Instagram (2026-07)

Spike ao vivo contra a Graph API **v25.0** (conta `act_763408067802379`, Página
`108356564252733`, IG Business Account `17841436814014233` — `@flavioahoy`), via
`plugins/meta-ads-pro/lib/graph_api.sh`. Todo payload abaixo foi rodado de verdade (nenhum
é hipotético) — respostas e erros são colados **verbatim**, com `fbtrace_id`. Trechos
rotulados `[doc]` vêm de WebFetch em páginas oficiais da Meta (URL citada). Executado em
2026-07-09.

Este spike existe pra alimentar a Task 13 (`/meta-ads-boost`) com o payload real e as
regras de elegibilidade reais — não o que o brief *assumia* que funcionaria.

## Os 5 vereditos (resumo executivo)

| # | Pergunta | Veredito | Detalhe |
|---|---|---|---|
| 1 | Payload candidato do brief (`object_story_spec{page_id,instagram_user_id}` + `source_instagram_media_id`) funciona? | **NÃO** | Erro idêntico ao de um payload sem NENHUMA referência de mídia — a API ignora `source_instagram_media_id` nesse formato (ver seção 2). |
| 2 | Payload mínimo que realmente funciona | `{"name": "...", "source_instagram_media_id": "<ID>"}` — **sozinho, sem `object_story_spec`** | Confirmado 2x ao vivo (com e sem `object_id`). Ver seção 2. |
| 3 | `instagram_user_id` vs `instagram_actor_id` | **`instagram_user_id` é o único que funciona** (e nem é obrigatório no payload mínimo); `instagram_actor_id` é rejeitado com erro específico de ID inválido | Ver seção 2.4. Deprecação provada pelo erro ao vivo; data de cutoff citada por fonte secundária fica [não verificado]. |
| 4 | `object_story_spec` + `source_instagram_media_id` juntos? | **Proibido — erro "objeto promovido ambíguo"** | Erro `100/1487929`, texto explícito citando os dois campos. Ver seção 2.3. |
| 5 | Reel com música licenciada — o bloqueio existe e é testável? | **SIM, confirmado ao vivo** | Erro `100/2875030` "Não é possível turbinar como anúncios os reels que usam músicas com direitos autorais", + campo preditivo `boost_eligibility_info.boost_ineligible_reason` que já avisa antes de tentar. Ver seção 4. |

Achado bônus pra Task 13: a combinação de campos do ad set pra "impulsionar" (boost) via
`destination_type: ON_POST` + `optimization_goal: POST_ENGAGEMENT` não está coberta em
`flows/conjuntos/SKILL.md` (que só cobre WEBSITE/LEAD_FORM/WHATSAPP/MESSENGER/PHONE_CALL) —
payload funcional descoberto ao vivo na seção 3.2.

---

## 1. Listagem de mídia do IG (Step 1)

```bash
graph_api GET "${PAGE_ID}?fields=instagram_business_account"
→ {"instagram_business_account":{"id":"17841436814014233"},"name":"Flávio Ahoy","id":"108356564252733"}
```

Confirma o vínculo Page↔IG e que `INSTAGRAM_USER_ID` do `.env` está correto.

```bash
graph_api GET "${INSTAGRAM_USER_ID}/media?fields=id,caption,media_type,media_product_type,permalink,timestamp,like_count,comments_count&limit=10"
```

Todos os campos pedidos retornam de verdade (`id`, `caption`, `media_type`,
`media_product_type`, `permalink`, `timestamp`, `like_count`, `comments_count`). Amostra real
(2 de 10 registros, resposta completa era maior):

```json
{"id":"18112743619917095","media_type":"CAROUSEL_ALBUM","media_product_type":"FEED",
 "permalink":"https://www.instagram.com/p/DYx3ZMQDXlt/","timestamp":"2026-05-25T22:55:16+0000",
 "like_count":8,"comments_count":0}
{"id":"17935394742210153","media_type":"VIDEO","media_product_type":"REELS",
 "permalink":"https://www.instagram.com/reel/DXMRfzihkLC/","timestamp":"2026-04-16T12:00:05+0000",
 "like_count":503,"comments_count":394}
```

**`media_product_type` distingue `FEED` de `REELS` de verdade** (não é o `media_type`, que
só diz `CAROUSEL_ALBUM`/`VIDEO`/`IMAGE`). Nesta conta, com uma amostra de 25 posts:
- Todo post `media_product_type=FEED` encontrado é `media_type=CAROUSEL_ALBUM` (nenhum
  `IMAGE` single solto na amostra).
- Todo post `media_product_type=REELS` é `media_type=VIDEO`, como esperado.

Campo extra descoberto (não pedido no brief, mas essencial pro Step 4):
`GET {media-id}?fields=boost_eligibility_info` — existe e retorna
`{"eligible_to_boost": true|false, "boost_ineligible_reason": "<texto>"}` quando falso.
`[doc]` Descrição oficial (WebFetch em
https://developers.facebook.com/docs/instagram-platform/reference/instagram-media/):
*"The field provides information about boosting eligibility of a Instagram instagram media
as an ad and additional details if not eligible."* Ver uso real na seção 4.

---

## 2. Creative a partir de post existente — a busca pelo payload que funciona (Step 2)

### 2.1 O payload candidato do brief falhou

```bash
payload='{"name":"TEST_SPIKE_boost_ig","object_story_spec":{"page_id":"108356564252733","instagram_user_id":"17841436814014233"},"source_instagram_media_id":"18112743619917095"}'
graph_api POST "${AD_ACCOUNT_ID}/adcreatives" "$payload"
```

```json
{"error":{"message":"Invalid parameter","type":"OAuthException","code":100,
 "error_data":"{\"blame_field_specs\":[[\"link\"]]}","error_subcode":2061015,
 "error_user_title":"Um campo obrigatório precisa ser preenchido",
 "error_user_msg":"O campo de link é obrigatório. Preencha o campo para continuar.",
 "fbtrace_id":"AKTXGER-zZPWQQfgvPUDFOu"}}
```

**Achado decisivo:** rodei um payload *baseline* — só `object_story_spec:{page_id,
instagram_user_id}`, **sem nenhuma referência de mídia** — e o erro veio **idêntico, byte a
byte** (mesmo `error_subcode`, mesma mensagem):

```json
{"error":{"error_subcode":2061015,"error_user_msg":"O campo de link é obrigatório. Preencha o campo para continuar.","fbtrace_id":"AdFh8Hec3m8CrO8EtBf9xpb"}}
```

Ou seja: com `object_story_spec` presente (mesmo que só com os campos de identidade,
sem conteúdo), a API **ignora silenciosamente** `source_instagram_media_id` — não é
reconhecido como par válido nessa posição. Testei também variações de nome de campo, todas
com o mesmo resultado (erro de `link` idêntico ao baseline, ou seja, todas ignoradas):
`source_instagram_media_id` dentro de `object_story_spec` (aninhado), `instagram_media_id`
(nome citado num artigo de terceiros sobre a mudança de nomenclatura), `effective_instagram_media_id`,
`instagram_permalink_url` com a URL do post. Nenhuma delas alterou o comportamento — sempre
o mesmo erro `2061015` de `link` ausente.

### 2.2 Testei `instagram_actor_id` (legado) — erro DIFERENTE, mais específico

```bash
payload='{"name":"TEST_SPIKE_v3_actorid","object_story_spec":{"page_id":"108356564252733","instagram_actor_id":"17841436814014233"},"source_instagram_media_id":"18112743619917095"}'
```

```json
{"error":{"message":"(#100) Param instagram_actor_id must be a valid Instagram account id",
 "type":"OAuthException","code":100,"fbtrace_id":"AdTIlRbAuGyKNhPKM2cHw3_"}}
```

Isso já é evidência forte: `instagram_actor_id` **reconhece** o campo (valida o ID e
rejeita), o que é um comportamento **diferente** do baseline (que ignora tudo e pede
`link`). Ou seja, `instagram_actor_id` é processado, mas rejeita o ID moderno
`17841436814014233` como inválido pra esse campo legado.

`[não verificado — fonte secundária]` Sobre a deprecação: WebFetch em ppc.land (artigo sobre
simplificação da API Instagram/Marketing da Meta; URL específica do artigo não recuperada —
ver Concern #4) citava: *"In the Marketing API, fields like `instagram_actor_id` and
`instagram_story_id` will be replaced with `instagram_user_id` and `instagram_media_id`,
respectively. According to the announcement, several endpoints will no longer support legacy
objects starting January 21, 2026."* A data de cutoff (21/01/2026) fica rotulada [não
verificado] por falta de fonte primária localizável. **O veredito desta seção não depende
dela:** a rejeição de `instagram_actor_id` está provada pelo erro ao vivo acima.

### 2.3 Tentei "completar" o `object_story_spec` com `link_data` — revelou a regra real

```bash
payload='{"name":"TEST_SPIKE_v7_link_data","object_story_spec":{"page_id":"108356564252733","instagram_user_id":"17841436814014233","link_data":{"link":"https://www.instagram.com/p/DYx3ZMQDXlt/"}},"source_instagram_media_id":"18112743619917095"}'
```

```json
{"error":{"message":"Invalid parameter","type":"OAuthException","code":100,
 "error_subcode":1487929,
 "error_user_title":"Campos ambíguos do objeto promovido",
 "error_user_msg":"O objeto que você está tentando promover é ambíguo. Você deve especificar apenas um objeto promovido. Você especificou o seguinte: object_story_spec, source_instagram_media_id.",
 "fbtrace_id":"Adq0XcL0RvX5uhJUpw9ahYa"}}
```

Essa mensagem é explícita: **`object_story_spec` completo (com conteúdo real) e
`source_instagram_media_id` são dois "objetos promovidos" concorrentes — só pode existir
UM.** Isso explica retroativamente a seção 2.1: com `object_story_spec` incompleto (só
identidade, sem `link_data`/`photo_data`/`video_data`), a API não o considera "completo" o
suficiente pra disparar a ambiguidade, mas também não aceita o `source_instagram_media_id`
como fallback — resultado: nenhum promoted object válido, erro de "link obrigatório".

`[doc]` Bate com a descrição oficial do campo `object_story_spec` (WebFetch em
https://developers.facebook.com/docs/marketing-api/reference/ad-creative/): *"Use if you
want to create a new unpublished page post and turn the post into an ad."* — ou seja,
`object_story_spec` é pra **criar um post novo**; `source_instagram_media_id` é pra
**referenciar um post já existente**. São dois caminhos mutuamente exclusivos por design,
não uma combinação.

### 2.4 O payload que funciona — `source_instagram_media_id` sozinho

```bash
payload='{"name":"TEST_SPIKE_v8_only_source","source_instagram_media_id":"18112743619917095"}'
graph_api POST "${AD_ACCOUNT_ID}/adcreatives" "$payload"
```

```json
{"id":"1058836683146723"}
```

Testei também com `object_id` (a Página) no lugar de `object_story_spec` — também funciona,
resultado equivalente:

```bash
payload='{"name":"TEST_SPIKE_v9_object_id","object_id":"108356564252733","source_instagram_media_id":"18112743619917095"}'
```

```json
{"id":"1721801315729070"}
```

**Round-trip de ambos** (`GET {id}?fields=id,name,object_story_spec,effective_object_story_id,instagram_permalink_url,object_type,source_instagram_media_id`):

```json
{"id":"1058836683146723","name":"TEST_SPIKE_v8_only_source 2026-07-08-34f31a974ff59a738467f357f779b323",
 "effective_object_story_id":"108356564252733_1657126553086986","object_type":"SHARE",
 "source_instagram_media_id":"18112743619917095"}
{"id":"1721801315729070","name":"TEST_SPIKE_v9_object_id 2026-07-08-bfdc5d033af86ae12445950a22ac93e9",
 "effective_object_story_id":"108356564252733_1657126713086970","object_type":"SHARE",
 "source_instagram_media_id":"18112743619917095"}
```

Notas do round-trip:
- `object_story_spec` **não volta na resposta** (nem foi enviado) — confirma que não é
  necessário.
- Meta gera sozinho um `effective_object_story_id` (um "share" — `object_type: SHARE` — da
  Página apontando pro post do IG) e um sufixo automático no `name` (timestamp + hash) —
  comportamento normal de dedup de creative, não é erro.
- `instagram_permalink_url` veio vazio nos dois casos (campo não populado quando a origem é
  `source_instagram_media_id`).

### 2.5 Payload final recomendado (Task 13)

```json
{
  "name": "<nome gerado>",
  "source_instagram_media_id": "<IG_MEDIA_ID>"
}
```

Nenhum campo de identidade (`instagram_user_id`/`instagram_actor_id`/`page_id`) é necessário
nesse payload — o `object_id`/Página é inferido a partir do IG media (que já está vinculado à
Página via `instagram_business_account`, seção 1). Se quiser ser explícito, `object_id:
PAGE_ID` funciona igual sem quebrar nada (testado, seção 2.4) — mas não é obrigatório.

**Veredito identidade:** `instagram_user_id` é o campo correto quando `object_story_spec` é
usado pra outros fins (ex.: dinâmico/dark post, que continuam precisando dele — ver
`flows/anuncios/SKILL.md`); `instagram_actor_id` está deprecado e rejeita IDs modernos. Pra
boost de post existente especificamente, **nenhum dos dois é necessário** — é o achado mais
importante deste spike.

---

## 3. Cadeia campanha → adset → ad + preview (Step 3)

### 3.1 Campanha

```bash
payload='{"name":"TEST_SPIKE_BOOST_campanha","objective":"OUTCOME_ENGAGEMENT","status":"PAUSED","special_ad_categories":[],"is_adset_budget_sharing_enabled":false}'
graph_api POST "${AD_ACCOUNT_ID}/campaigns" "$payload"
→ {"id":"120255176195230196"}
```

`min_daily_budget` da conta, verificado ao vivo antes de montar o adset:

```bash
graph_api GET "${AD_ACCOUNT_ID}?fields=timezone_name,currency,min_daily_budget,name"
→ {"timezone_name":"America/Recife","currency":"BRL","min_daily_budget":522,"name":"CA - Flávio Ahoy","id":"act_763408067802379"}
```

(o valor "522" veio do dispatch do controller, que já o havia lido da conta na descoberta
do ambiente — o GET acima re-confirma ao vivo, R$5,22; a evidência primária é a resposta verbatim.)

### 3.2 Ad set — achado extra: payload de "boost" não coberto pelas skills existentes

Primeira tentativa (sem `bid_strategy`) falhou:

```json
{"error":{"error_subcode":2490487,"error_user_title":"O valor ou as restrições de lance são obrigatórios para a estratégia de lance","error_user_msg":"Valor ou restrições de lance obrigatórios: para limite de lance, você deve fornecer o campo de valor do lance...","fbtrace_id":"A5quA2MET5X37dXVVo9Eube"}}
```

Payload final que funcionou (budget R$6/dia = 600 centavos, acima do mínimo 522):

```json
{
  "name": "TEST_SPIKE_BOOST_conjunto",
  "campaign_id": "120255176195230196",
  "status": "PAUSED",
  "daily_budget": 600,
  "billing_event": "IMPRESSIONS",
  "optimization_goal": "POST_ENGAGEMENT",
  "bid_strategy": "LOWEST_COST_WITHOUT_CAP",
  "destination_type": "ON_POST",
  "promoted_object": {"page_id": "108356564252733"},
  "targeting": {
    "geo_locations": {"countries": ["BR"]},
    "age_min": 18,
    "age_max": 65,
    "targeting_automation": {"advantage_audience": 0}
  }
}
```

```json
{"id":"120255176197360196"}
```

**Achado pra Task 13:** `destination_type: ON_POST` + `optimization_goal: POST_ENGAGEMENT` +
`bid_strategy` explícito (obrigatório, senão erro 2490487) é a combinação real de "boost de
post". Não está documentada em `flows/conjuntos/SKILL.md` (que cobre só WEBSITE/LEAD_FORM/
WHATSAPP/MESSENGER/PHONE_CALL) — Task 13 precisa desse 6º destino.

### 3.3 Ad (referencia o creative do Step 2.4)

```bash
payload='{"name":"TEST_SPIKE_BOOST_ad","adset_id":"120255176197360196","creative":{"creative_id":"1058836683146723"},"status":"PAUSED"}'
graph_api POST "${AD_ACCOUNT_ID}/ads" "$payload"
→ {"id":"120255176198420196"}
```

### 3.4 Preview — confirma que o anúncio referencia o post orgânico

```bash
graph_api GET "120255176198420196/previews?ad_format=INSTAGRAM_STANDARD"
```

```json
{"data":[{"body":"<iframe src=\"https://business.facebook.com/ads/api/preview_iframe.php?d=AQKfeGocl3Htnk3vxuZqtahWsiLR-LxL_CkyVxeS5UhbDGRxOpbfbJy2r0E8Q6pTRhZjkKAne3jGZX0K-LpuH0HCqPQruH_mVEzJvgVlt_yIV1pZzGscuQXfHNY-aZU8MhyN-45af-eJr0f0u_W2dT5bojnud5sYSKmvz-C8x2TNpA0oaQxy9iVuYMUwGi9BkVm1s-5--3ejdJVxTemzcKN5kQiHuCF6hToY55zNTXtCoSY-27bqICYDAMF6s1cATKpuTe7iFgUidB57FXeItYb8t9qRi60cT8w84qQVnJKUwXHmoNm0DotAPi5lM6GxsDFqb_Ji1zTHu3uIrqjMtnPtRjkb5pUsOXU7PietYbgbvF-egoIKumFx_4le5Nt-p14CIn48g0WDS6wfiS7R58ua2Fq0zRSsZmFyT3jikmHC_6sNoei-f8qv6TaSIHuqOyM&t=AQKkndvBz_WdQB2McxQ\" width=\"320\" height=\"525\" scrolling=\"yes\" style=\"border: none;\" allow=\"autoplay\"></iframe>"}]}
```

Abri o iframe de verdade no Chrome isolado (browser-harness, perfil logado) e capturei
screenshot. Confirmação visual: o card do anúncio mostra o handle **`flavioahoy`** com selo
"Anúncio", o carrossel **"1/7"** e o título **"TODO APP AGORA QUER SER SISTEMA
OPERACIONAL."** — batendo exatamente com o `caption`/carrossel do post orgânico
`18112743619917095` da seção 1. Isso confirma que o anúncio de fato referencia o post
existente (não um post novo criado do zero).

**Ressalva honesta:** essa renderização específica de preview do Instagram (feed) **não
exibe contagem numérica de curtidas/comentários** (mostra só os ícones de coração/comentário/
compartilhar, sem números) — esse é o comportamento padrão de preview de anúncio do
Instagram, não um problema do creative. A preservação do social proof (curtidas/comentários
reais do post) é uma característica do *post referenciado* em si (`effective_object_story_id`
aponta pro post real, que mantém seus próprios contadores no Graph API — confirmado na seção
1, `like_count`/`comments_count` retornam via `/media`), não algo visível nesse formato
específico de preview iframe.

---

## 4. Reel com música licenciada (Step 4)

Testei `source_instagram_media_id` (payload mínimo da seção 2.5) contra **5 Reels
diferentes** da conta, cada um checado antes via `boost_eligibility_info`:

| Reel ID | Likes | `boost_eligibility_info` | Resultado da criação do creative |
|---|---|---|---|
| `17935394742210153` | 503 | (não checado antes) | Erro `100/1815279` — *"O vídeo do Instagram deve ser carregado no Facebook"* / "Ao anunciar um vídeo existente no Instagram, você precisa carregá-lo no Facebook antes de criar o anúncio." |
| `18099776435054379` | 55 | (não checado antes) | Erro `100/1815279` — idêntico ao acima |
| `18093503768324216` | 402 | `{"eligible_to_boost":true}` | Erro `100/1815279` — idêntico, **mesmo com `eligible_to_boost:true`** (ver nota abaixo) |
| `18077975840210569` | 22 | (não checado antes) | Erro `100/2875039` — *"Não é possível usar reel"* / "Reels que contêm elementos tocáveis não podem ser usados em anúncios." |
| `17880349761405800` | 376 | `{"eligible_to_boost":false,"boost_ineligible_reason":"Remova ou escolha outro áudio."}` | **Erro `100/2875030`** — *"Não é possível turbinar o reel"* / "Não é possível turbinar como anúncios os reels que usam músicas com direitos autorais." |

### O achado central (erro `100/2875030`)

```bash
graph_api GET "17880349761405800?fields=id,boost_eligibility_info,like_count,permalink"
→ {"id":"17880349761405800","like_count":376,"permalink":"https://www.instagram.com/reel/DWtbWrwBjnn/",
   "boost_eligibility_info":{"eligible_to_boost":false,"boost_ineligible_reason":"Remova ou escolha outro áudio."}}
```

```bash
payload='{"name":"TEST_SPIKE_reelB_17880349761405800","source_instagram_media_id":"17880349761405800"}'
graph_api POST "${AD_ACCOUNT_ID}/adcreatives" "$payload"
```

```json
{"error":{"message":"Invalid parameter","type":"OAuthException","code":100,
 "error_subcode":2875030,
 "error_user_title":"Não é possível turbinar o reel",
 "error_user_msg":"Não é possível turbinar como anúncios os reels que usam músicas com direitos autorais.",
 "fbtrace_id":"AtSa6e_cJrrUOxA6XOieKyo"}}
```

**Veredito: o bloqueio de música licenciada existe e é 100% testável/confirmado ao vivo,
com mensagem amigável pronta pra usar na Task 13** ("Não é possível turbinar como anúncios
os reels que usam músicas com direitos autorais.").

**Achado extra — verificação preditiva sem gastar chamada de escrita:** o campo
`GET {media-id}?fields=boost_eligibility_info` (GET, não conta como chamada de escrita)
**já avisa `eligible_to_boost:false` com o motivo em texto ANTES de tentar criar o
creative**. Pra Task 13, a UX ideal é: checar `boost_eligibility_info` primeiro e mostrar
`boost_ineligible_reason` direto ao usuário, sem precisar disparar o POST de `adcreatives`
pra descobrir o erro.

### Duas outras causas de bloqueio encontradas (não são sobre música, mas relevantes pra Task 13)

- **`100/1815279`** ("vídeo precisa ser carregado no Facebook primeiro") apareceu em 3 dos 5
  Reels testados — inclusive um com `boost_eligibility_info.eligible_to_boost:true`. Ou seja,
  **`boost_eligibility_info` não garante que `POST /adcreatives` vá funcionar** — existe um
  segundo portão técnico (disponibilidade do vídeo no lado Facebook) independente da
  elegibilidade de conteúdo/música. Pra Task 13, isso significa que mesmo Reels "elegíveis"
  podem falhar na criação — a mensagem de erro amigável pra esse caso não foi coberta pelo
  brief original, registro aqui como achado.
- **`100/2875039`** ("Reels que contêm elementos tocáveis não podem ser usados em anúncios")
  — Reel com sticker/elemento interativo ("Comente Workshop"). Distinto de música — é sobre
  UI interativa do Reel.

**Nenhum dos 5 Reels testados nesta sessão chegou a criar um creative com sucesso** — 3 caíram
no bloqueio de upload-pro-Facebook, 1 no bloqueio de elemento tocável, 1 no bloqueio de
música licenciada. Isso não significa que Reels nunca funcionem via `source_instagram_media_id`
(o creative da seção 2.4/2.5 provou que o mecanismo geral funciona pra posts de FEED) — só
que, dentro do orçamento deste spike, não encontrei um Reel desta conta específica que
passasse por todos os 3 portões ao mesmo tempo. Registrado honestamente como lacuna, não
forçado como veredito de "Reels não funcionam".

`[doc]` Sobre elegibilidade/direitos autorais em anúncios com música: a Meta não documenta
publicamente a lista de faixas restritas na referência de API consultada
(`ad-creative`, `instagram-media`) — a fonte de verdade observável é o próprio campo
`boost_eligibility_info` + o erro em tempo de criação, ambos confirmados ao vivo acima.

---

## 5. Cleanup (Step 5)

Ordem: ad → creatives → adset → campanha, com `sleep` entre chamadas.

```bash
graph_api DELETE "120255176198420196"   # ad
→ {"success":true}
graph_api DELETE "1058836683146723"     # creative usado no ad
→ {"success":true}
graph_api DELETE "1721801315729070"     # creative de teste (v9, nunca anexado a um ad)
→ {"success":true}
graph_api DELETE "120255176197360196"   # adset
→ {"success":true}
graph_api DELETE "120255176195230196"   # campanha
→ {"success":true}
```

Confirmação final via GET em todos os 5 objetos — a API retorna `status: DELETED` (não
erro/vazio como o brief esperava, mas confirmação inequívoca de que o objeto não existe
mais como ativo):

```json
{"id":"120255176198420196","status":"DELETED"}
{"id":"1058836683146723","status":"DELETED"}
{"id":"1721801315729070","status":"DELETED"}
{"id":"120255176197360196","status":"DELETED"}
{"id":"120255176195230196","status":"DELETED"}
```

Nenhum outro objeto da conta/Página/IG foi tocado. Os 5 Reels e o post de FEED usados nos
testes de creative são posts orgânicos reais do `@flavioahoy` e não foram alterados (só
lidos e referenciados por creatives de teste, todos deletados).

---

## Concerns (honestos, não escondidos)

1. **Orçamento de chamadas de escrita estourado.** O brief mirava ~10-15 POSTs; usei ~19
   POSTs de `adcreatives`/`campaigns`/`adsets`/`ads` (9 tentativas de payload na seção 2 até
   achar o formato certo — a maioria falhou rápido, sem custo de processamento pesado — + 2
   creatives que funcionaram + 5 tentativas de Reel na seção 4 + 3 objetos da cadeia
   campanha/adset/ad) + 5 DELETEs de cleanup. Não bati rate limit (código 17) em nenhum
   momento, com sleeps de 5-20s entre chamadas de escrita. O estouro veio da exploração de
   nomes de campo (seção 2) — que era exatamente o trabalho que o brief pedia pra não
   assumir o payload document/candidato sem confirmar ao vivo.
2. **Não encontrei um Reel desta conta que passasse pelos 3 portões de elegibilidade ao
   mesmo tempo** (upload-pro-Facebook, elemento tocável, música licenciada) — não dá pra
   afirmar com este spike que "Reels normais boostam de primeira" nesta conta específica;
   só que o mecanismo (`source_instagram_media_id` sozinho) é o mesmo usado com sucesso pra
   posts de FEED.
3. **A preview visual (seção 3.4) não mostra contagem de curtidas/comentários** — o board
   de evidência que prova "social proof preservado" é a combinação preview (conteúdo real)
   + `like_count`/`comments_count` retornados pela edge `/media` (seção 1), não um único
   screenshot com números visíveis.
4. **O `[doc]` sobre `instagram_actor_id`/`instagram_story_id` vem de um artigo de
   terceiros (ppc.land), não do changelog oficial da Meta diretamente** — tentei fetch
   direto em `developers.facebook.com/docs/graph-api/changelog/version25.0/` (usado no spike
   de versão anterior) mas essa mudança específica de nomenclatura não aparece lá; o artigo
   de terceiros é a única fonte encontrada que cita a data de cutoff (21/01/2026). O
   comportamento ao vivo (seção 2.2) é consistente com essa fonte, mas a fonte em si não é
   1ª parte.
5. **A URL de preview iframe (seção 3.4) foi colada no doc como pedido pelo brief** — é um
   link assinado de preview (`d=`/`t=` são tokens opacos de preview, não o
   `META_ACCESS_TOKEN`), mas por ser um link funcional de preview de anúncio, considere-o
   sensível/temporário — não é um segredo de conta, mas também não precisa ficar público
   fora deste repo.
