---
name: meta-ads-boost
description: Impulsionar post ou Reel JÁ PUBLICADO do Instagram como anúncio — preserva curtidas/comentários (social proof), sem dark post. Lista a mídia da conta, checa boost_eligibility_info antes de tentar, e cria creative+ad PAUSED via adset existente ou novo (destino ON_POST). Payloads verificados ao vivo em docs/spikes/2026-07-boost-ig.md.
---

# meta-ads-boost

Impulsiona (boost) um post ou Reel que já existe no feed do Instagram, mantendo curtidas/comentários/permalink do post orgânico — diferente de `flows/anuncios/SKILL.md`, que cria um post novo (dark post ou live) a partir de mídia solta. Invocada pela orquestradora ou direto via `/meta-ads-boost`.

**Base de payload:** todo formato de creative/adset abaixo foi confirmado ao vivo contra a Graph API v25.0 em `docs/spikes/2026-07-boost-ig.md` — esse spike é autoritativo sobre qualquer suposição anterior de payload.

## Quando usar

- `/meta-ads-boost` — invocação direta
- Orquestradora roteia aqui quando o user pede "impulsionar", "boost", "patrocinar post/reel", "turbinar publicação"

## Fluxo de execução (6 passos)

### Passo 1 — Pre-flight

Se invocada direta (sem `CURRENT_RUN_ID`), roda `lib/preflight.sh` em modo `--silent` antes de tudo (mesmo padrão de `flows/campanha/SKILL.md` Passo 1).

Check adicional, específico deste flow (o doctor genérico **não** valida isso — `check_claude_md_config` em `lib/preflight.sh` só exige `ad_account_id`/`page_id`/`nomenclatura_style`):

```bash
grep -q '^instagram_user_id:' CLAUDE.md 2>/dev/null || {
  echo "✗ instagram_user_id ausente em CLAUDE.md — rode /meta-ads-setup (Passo 8, descoberta de Instagram) antes de usar boost."
  exit 2
}
```

Carrega `AD_ACCOUNT_ID`, `PAGE_ID`, `INSTAGRAM_USER_ID` do CLAUDE.md/env.

### Passo 2 — Listar mídia do Instagram

```bash
graph_api GET "${INSTAGRAM_USER_ID}/media?fields=id,caption,media_type,media_product_type,permalink,timestamp,like_count,comments_count&limit=25"
```

Todos os campos pedidos retornam de verdade (confirmado ao vivo, spike seção 1). Renderiza tabela:

```
# | Data       | Tipo  | Curtidas | Comentários | Caption (60c)                | Link
1 | 2026-05-25 | FEED  | 8        | 0           | "Todo app agora quer ser..." | instagram.com/p/DYx3ZMQDXlt/
2 | 2026-04-16 | REELS | 503      | 394         | "..."                        | instagram.com/reel/DXMRfzihkLC/
```

Usa `media_product_type` pra distinguir FEED de REELS (**não** `media_type` — esse só diz `CAROUSEL_ALBUM`/`VIDEO`/`IMAGE`, spike seção 1). Paginação via cursors (`paging.next`) se o user pedir mais que os 25 exibidos.

### Passo 3 — Escolha + checagem de elegibilidade (ANTES de gastar uma chamada de escrita)

User escolhe 1..N pela tabela. **Pra cada mídia escolhida**, antes de qualquer POST:

```bash
graph_api GET "${media_id}?fields=boost_eligibility_info"
# → {"eligible_to_boost": true}
# → {"eligible_to_boost": false, "boost_ineligible_reason": "Remova ou escolha outro áudio."}
```

Esse campo existe e responde de verdade (GET, sem custo de escrita — confirmado ao vivo, spike seção 1 e 4). Se `eligible_to_boost == false`:

```
✗ "#{caption resumido}" não pode ser impulsionado: {boost_ineligible_reason}
   Escolha outra mídia da lista, ou pule esta.
```

**Não aborta o fluxo inteiro** — remove só essa mídia da fila e segue com as demais.

**Ressalva honesta (spike seção 4):** `eligible_to_boost: true` **não garante** que o `POST /adcreatives` do Passo 5 vá funcionar — existe um segundo portão técnico independente da elegibilidade de conteúdo (ex.: vídeo do Reel ainda não replicado pro lado Facebook). Por isso o Passo 5 também trata falha por mídia individual, não aborta o lote inteiro.

Erros catalogados encontrados ao vivo pra essa etapa (mostrar a `error_user_msg` da Meta, que já vem em PT-BR):

| `error_subcode` | Causa | Mensagem amigável (verbatim da Meta) |
|---|---|---|
| `100/2875030` | Reel usa música com direitos autorais | "Não é possível turbinar como anúncios os reels que usam músicas com direitos autorais." |
| `100/2875039` | Reel tem elemento tocável (sticker interativo) | "Reels que contêm elementos tocáveis não podem ser usados em anúncios." |
| `100/1815279` | Vídeo do Reel ainda não replicado pro Facebook (independe de `boost_eligibility_info`) | "Ao anunciar um vídeo existente no Instagram, você precisa carregá-lo no Facebook antes de criar o anúncio." |

### Passo 4 — Campanha/conjunto

```
[1] Usar adset existente — lista via /meta-ads-campanha list + adsets da campanha escolhida (default)
[2] Criar novos
```

**[1] Adset existente:** vale só se o adset já tiver `destination_type: ON_POST` + `optimization_goal: POST_ENGAGEMENT` (senão o ad não deveria entrar nele — Meta rejeita mismatch de goal/destino). Filtra a listagem por isso antes de oferecer ao user.

**[2] Criar novos:**

1. Cria campanha via `/meta-ads-campanha --no-chain` com objetivo `OUTCOME_ENGAGEMENT` (impede o encadeamento automático pro `/meta-ads-conjuntos` — ver nota abaixo).
2. Cria o **ad set aqui mesmo**, não via `/meta-ads-conjuntos`. **Achado do spike (seção 3.2):** o destino "boost de post" (`destination_type: ON_POST` + `optimization_goal: POST_ENGAGEMENT`) não está entre os 5 destinos suportados por `flows/conjuntos/SKILL.md` (WEBSITE/LEAD_FORM/WHATSAPP/MESSENGER/PHONE_CALL) — delegar pra lá quebraria. Reaproveita a mesma UX de perguntas daquele flow (geo no Passo 3, idade no Passo 4, gênero no Passo 5, `advantage_audience` sempre presente no Passo 8), mas monta o payload final assim:

```json
{
  "name": "{nome via gen_name}",
  "campaign_id": "{campaign_id}",
  "status": "PAUSED",
  "daily_budget": {budget_cents},
  "billing_event": "IMPRESSIONS",
  "optimization_goal": "POST_ENGAGEMENT",
  "bid_strategy": "LOWEST_COST_WITHOUT_CAP",
  "destination_type": "ON_POST",
  "promoted_object": {"page_id": "{PAGE_ID}"},
  "targeting": {
    "geo_locations": {"countries": ["BR"]},
    "age_min": 18,
    "age_max": 65,
    "targeting_automation": {"advantage_audience": 0}
  }
}
```

**`bid_strategy` é OBRIGATÓRIO** nesse payload — omissão dispara `100/2490487` ("Valor ou restrições de lance obrigatórios", confirmado ao vivo, spike seção 3.2). Oferece as mesmas 5 opções de `flows/campanha/SKILL.md` Passo 7 (default `LOWEST_COST_WITHOUT_CAP`). Valida `daily_budget >= min_daily_budget` da conta (`GET ${AD_ACCOUNT_ID}?fields=min_daily_budget`).

`manifest_add adset $adset_id` após o POST.

### Passo 5 — Creative + Ad (PAUSED)

**Payload do creative — forma final provada ao vivo (spike seção 2.5), NÃO a do rascunho original:**

```bash
payload=$(jq -nc --arg name "$(gen_name ad "${NOMENCLATURA_STYLE}" formato="boost" nome-criativo="$media_id" avatar="post" tipo="engagement" cta="none" N="01")" \
  --arg m "$media_id" \
  '{name: $name, source_instagram_media_id: $m}')
creative_id=$(graph_api POST "${AD_ACCOUNT_ID}/adcreatives" "$payload" | jq -r .id)
```

**Regra inviolável: NUNCA incluir `object_story_spec`, `page_id`, `instagram_user_id` ou `instagram_actor_id` nesse payload.** O spike provou 3 formas diferentes de quebrar isso:

- `object_story_spec` incompleto (só `page_id`+`instagram_user_id`, sem conteúdo) junto com `source_instagram_media_id` → API **ignora silenciosamente** o `source_instagram_media_id` e erra pedindo `link` (`100/2061015`) — o payload do brief original caía exatamente aqui.
- `object_story_spec` completo (com `link_data`) junto com `source_instagram_media_id` → erro explícito de ambiguidade (`100/1487929`, "Você deve especificar apenas um objeto promovido").
- `instagram_actor_id` no lugar de `instagram_user_id` → rejeitado como ID inválido (campo legado, deprecado).

`object_id`/Página **não precisa ser explícito** — é inferido do vínculo Page↔IG do próprio media. Se quiser ser explícito sem quebrar nada, `object_id: PAGE_ID` funciona igual (testado, spike seção 2.4), mas não é obrigatório.

Registra: `manifest_add adcreative $creative_id`.

**Ad:**

```bash
ad_payload=$(jq -nc --arg n "$(gen_name ad ...)" --arg aid "$adset_id" --arg cid "$creative_id" \
  '{name: $n, adset_id: $aid, creative: {creative_id: $cid}, status: "PAUSED"}')
ad_id=$(graph_api POST "${AD_ACCOUNT_ID}/ads" "$ad_payload" | jq -r .id)
```

Registra: `manifest_add ad $ad_id`.

**Se o POST do creative falhar (Passo 3, ressalva):** mostra a `error_user_msg` da Meta, remove essa mídia da fila, e continua com as próximas mídias escolhidas — não aborta o lote inteiro nem faz rollback do adset/campanha (esses só entram no manifest depois de já criados com sucesso).

**NÃO aplicar UTM dinâmico** (`lib/utm.sh`) — o destino do boost é o próprio post orgânico, sem `link_url` externo. Anexar CTA com link externo num boost não foi testado neste spike; fica fora do escopo desta versão do flow (não fabricar suporte não verificado).

### Passo 6 — Resumo + preview + ativação

Mesmo padrão de `flows/anuncios/SKILL.md` Passos 11-12:

```
🚀 Ad de boost criado (PAUSED)

┌───┬────────────────────────────┬─────────────────┬───────────────────────────────┐
│ # │ Nome                       │ Ad ID           │ Post original                 │
├───┼────────────────────────────┼─────────────────┼───────────────────────────────┤
│ 1 │ boost_18112743619917095_v1 │ 120255176198420196 │ instagram.com/p/DYx3ZMQDXlt/ │
└───┴────────────────────────────┴─────────────────┴───────────────────────────────┘

🔗 Ads Manager: https://adsmanager.facebook.com/adsmanager/manage/ads?act=<account>&selected_ad_ids=<id>

Gerando preview oficial (post real renderizado)... aberto no browser.

Quer ativar? [s/n]
```

**Preview oficial é o default no boost (Task 14):** logo após criar o ad (antes de perguntar "Quer ativar?"), chama `preview_meta_oficial <creative_id> INSTAGRAM_STANDARD` (`lib/visual-preview.sh`) — usa o `creative_id` do Passo 5 (não precisa montar spec inline, o creative já existe). Formato default `INSTAGRAM_STANDARD`; se a mídia original for Reel/Story, usar `INSTAGRAM_REELS`/`INSTAGRAM_STORY` no lugar (conforme `media_product_type` lido no Passo 2). Abre automaticamente no browser (`open`/`xdg-open`) o HTML com o iframe oficial — sem perguntar antes (diferente do fluxo `anuncios`, onde o preview é opcional/perguntado). Faz sentido ser default aqui, e não em `anuncios`: o boost sempre referencia um `creative_id` já existente (sem spec pra montar, sem passo extra de escolha), e o preview fiel é o jeito mais direto de confirmar que o ad referencia o post orgânico certo antes de ativar.

Se o preview oficial falhar (ex.: rate limit momentâneo), cai pro fallback manual: `graph_api GET "{ad_id}/previews?ad_format=INSTAGRAM_STANDARD"` → abre o iframe retornado manualmente. Não bloqueia o fluxo — é só visual, o ad já foi criado (PAUSED) nesse ponto; a pergunta "Quer ativar?" segue normalmente mesmo se o preview falhar.

**Ressalva sobre o preview (spike seção 3.4):** o formato `INSTAGRAM_STANDARD` confirma visualmente que o anúncio referencia o post/carrossel original (handle, selo "Anúncio", mesmo conteúdo), mas **não exibe contagem numérica** de curtidas/comentários (só ícones) — isso é comportamento padrão do preview, não falha do creative. O social proof real (curtidas/comentários) vive no post referenciado e é visível via `like_count`/`comments_count` do Passo 2, ou abrindo o `permalink` direto.

Se `s` (ativar): `POST /{campaign_id} {"status":"ACTIVE"}` (se criada agora) → `POST /{adset_id} {"status":"ACTIVE"}` → `POST /{ad_id} {"status":"ACTIVE"}`.

## Regras invioláveis

1. **Sempre PAUSED na criação** — ACTIVE só no Passo 6 com confirmação explícita.
2. **Creative do boost = `{name, source_instagram_media_id}` sozinho** — nunca combinar com `object_story_spec`/`page_id`/`instagram_user_id`/`instagram_actor_id` (spike seção 2).
3. **Checar `boost_eligibility_info` antes de tentar** — GET barato antes de qualquer POST (Passo 3).
4. **`bid_strategy` sempre explícito** no adset ON_POST — omissão quebra com `100/2490487` (Passo 4).
5. **Falha de elegibilidade por mídia individual não aborta o lote** — remove da fila e segue (Passo 3 e 5).
6. **Nunca UTM dinâmico** no boost — destino é o post orgânico, sem link externo.
7. **Rollback via manifest** se qualquer passo 4-5 falhar de forma não recuperável (via `rollback_run`, mesma topologia: ad → adcreative → adset → campaign).

## Dependências de libs

- `lib/graph_api.sh` — wrapper POST/GET/DELETE com retry + error-resolver
- `lib/nomenclatura.sh` — `gen_name` pro nome do creative/ad
- `lib/rollback.sh` — `manifest_add` / `rollback_run`
- `lib/preflight.sh` — pre-flight silencioso quando invocada direta
- `lib/visual-preview.sh` — preview ASCII (reaproveita o mesmo helper de `flows/anuncios`) + `preview_meta_oficial` (default deste flow, Task 14)

## Referência

`docs/spikes/2026-07-boost-ig.md` — spike ao vivo completo (payloads, respostas verbatim com `fbtrace_id`, os 5 vereditos). Autoritativo sobre qualquer payload assumido em versões anteriores deste flow.
