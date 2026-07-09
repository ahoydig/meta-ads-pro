---
name: meta-ads-anuncios
description: Criar anúncios Meta Ads em 3 modos (Normal 1:1, Dinâmico asset_feed_spec, ou Carrossel child_attachments). Upload multipart cross-platform, dev mode fallback transparente via dark post, cache de media_fbid anti-reuso, geração de copy com humanizer, preview ASCII/HTML. Fix dos bugs #3 (dev mode), #4 (cartesiano), #5 (media_fbid).
---

# meta-ads-anuncios

A sub-skill mais complexa do plugin. Suporta 3 modos de criativo (Normal/Dinâmico/Carrossel), 4 formatos (imagem/vídeo/carrossel/collection), upload cross-platform (sips/ImageMagick), geração de copy via Claude multimodal + humanizer.

## Quando usar

- `/meta-ads-anuncios` — invocação direta (apenas ads, campanha e adset já existem)
- Invocada pela orquestradora como passo final do fluxo completo (campanha → adset → **ads**)

## Fluxo de execução (12 passos)

### Passo 1 — Pre-flight

Recebe da orquestradora (ou carrega do env via CLAUDE.md se invocada direta):

- `CURRENT_RUN_ID` — manifest ativo em `~/.claude/meta-ads-pro/current/{run_id}.json`
- `AD_ACCOUNT_ID` — ex. `act_763408067802379`
- `PAGE_ID`, `INSTAGRAM_USER_ID` — identidades pro object_story_spec
- `FALLBACK_DARK_POST` — setada pelo preflight/doctor. `true` = app em dev mode → roteia pra dark post flow
- `CAMPAIGN_ID`, `ADSET_ID` — do fluxo completo (ou perguntados se invocação direta)

Se invocada direta sem `CURRENT_RUN_ID`, roda `lib/preflight.sh` silencioso e gera run_id.

### Passo 2 — Tipo de criativo (pergunta explícita — FIX BUG #4)

```
Qual tipo de criativo?

[1] Normal — 1 imagem/vídeo + 1 copy por ad (pareado 1:1)
    Ideal quando você quer controle total sobre cada combinação.
    Resultado: N ads (1 por par).

[2] Dinâmico (asset_feed_spec) — múltiplas imagens + múltiplas copies,
    Meta otimiza combinações automaticamente.
    Resultado: 1 ad único que Meta varia no leilão.
    Limites v25.0: 10 imgs OR 1 vídeo + 5 headlines + 5 descriptions +
    5 primary texts + 5 CTAs.

[3] Carrossel (2-10 cartões) — N imagens fixas, cada uma com seu próprio
    headline/descrição/link (child_attachments), rolagem lateral no feed.
    Resultado: 1 ad único com N cartões fixos (não é combinatório — a ordem
    de exibição pode variar via multi_share_optimized, mas os cartões em si
    não mudam como no Dinâmico).

Escolha [1/2/3]:
```

Se `[3]`, os passos 3 (matching Normal) e 4 (limites de `asset_feed_spec`) não
se aplicam — vai direto pra seção **Modo Carrossel** abaixo.

### Passo 3 — Se Normal: validar matching (FIX BUG #4)

Se `N imagens ≠ M copies`:

```
⚠ 3 imagens + 5 copies. Matching 1:1 impossível.

Opções:
[a] Trocar pra Dinâmico (1 ad com asset_feed_spec)
[b] Matching manual (você define cada par — interativo)
[c] Produto cartesiano explícito (N×M = 15 ads)
    ⚠ Budget diluído — só recomendado se budget > R$50/dia.
       Meta leva 3-5 dias pra identificar vencedores com 15 variantes.

Escolha [a/b/c]:
```

Flag `--cartesian` pula o warn e vai direto pra (c) — pra scripts.
**Nunca** executa cartesiano em Dinâmico (asset_feed_spec já é combinatório; 15 ads manuais duplicam o trabalho da Meta).

### Passo 4 — Se Dinâmico: validar limites v25.0

Recusa payload se exceder:

| Campo | Limite |
|-------|--------|
| `asset_feed_spec.images` | ≤10 |
| `asset_feed_spec.videos` | ≤1 |
| Ambos images + videos | **proibido** (nem mistura) |
| `asset_feed_spec.titles` | ≤5 |
| `asset_feed_spec.descriptions` | ≤5 |
| `asset_feed_spec.bodies` | ≤5 |
| `asset_feed_spec.call_to_action_types` | ≤5 |

Se user tentou 12 imagens:

```
⚠ Dinâmico aceita no máximo 10 imagens (você tem 12).
Escolha 10 pra usar, ou troque pra 1 vídeo (sem imagens).
```

### Modo Carrossel (Task 16)

Terceiro modo do Passo 2. Diferente do Dinâmico (`asset_feed_spec`, a Meta
combina automaticamente) e do Normal (N ads separados, 1 imagem cada), o
Carrossel é **1 ad único com N cartões fixos** —
`object_story_spec.link_data.child_attachments` — cada cartão com sua própria
imagem, headline (`name`), descrição e link.

1. **Coleta de N imagens (2–10 cartões).** Mesmo mecanismo do Passo 5 (paths,
   pasta ou URLs), mas valida a contagem antes de seguir:

   ```
   ⚠ Carrossel aceita de 2 a 10 cartões (você tem <N>).
   ```

   Limite confirmado na [doc oficial](https://developers.facebook.com/docs/marketing-api/guides/videoads/):
   *"A 2-10 element array of link objects required for carousel ads"* — e ela
   recomenda pelo menos 3 pra performance (2 é só pra integrações leves,
   resultado sub-ótimo). O teto de 10 **não foi testado ao vivo nesta task**
   (custaria 1 POST fadado a erro só pra confirmar um número já documentado) —
   `[não verificado ao vivo, fonte: doc oficial]`.

2. **Copy por cartão** — reusa o pipeline de geração do Passo 6 (`gen_copy` +
   humanizer obrigatório), mas gera **1 headline + 1 descrição por cartão**
   (não N variações pra escolher — cada cartão do carrossel é fixo, sem
   combinação automática como no Dinâmico):

   ```bash
   for i in "${!imagens[@]}"; do
     headline["$i"]=$(gen_copy headline 1 "${imagens[$i]}" "$objective" "$audience" "$voice_file" "$product")
     descricao["$i"]=$(gen_copy description 1 "${imagens[$i]}" "$objective" "$audience" "$voice_file" "$product")
   done
   ```

3. **Upload** — `upload_image` (Passo 7) por cartão. Cache por SHA256 poupa
   re-upload se 2+ cartões apontarem pro mesmo arquivo. **Testado ao vivo**
   (`tests/20-criativo-avancado.sh test_05_carousel`): a Meta aceita o MESMO
   `image_hash` repetido em múltiplos `child_attachments` — útil quando o
   cartão varia só texto/link, não a imagem.

4. **UTM dinâmico — POR CARTÃO (regra inviolável 8 se aplica a CADA cartão).**
   Diferente do Normal/Dinâmico (1 `link` por ad/variação), o Carrossel tem
   **N+1 links**: o `link` principal de `link_data` **e** um `link` dentro de
   CADA `child_attachments[]`. Todos passam por `build_utm_url_dynamic`,
   exceto deeplinks (pula como sempre — `is_external_url`):

   ```bash
   source "$CLAUDE_PLUGIN_ROOT/lib/utm.sh"

   is_external_url "$link_principal" && link_principal=$(build_utm_url_dynamic "$link_principal")
   for i in "${!cartoes_link[@]}"; do
     is_external_url "${cartoes_link[$i]}" && cartoes_link[$i]=$(build_utm_url_dynamic "${cartoes_link[$i]}")
   done
   ```

5. **Preview (Passo 8) — oficial recomendado.** O preview local (`preview_html`,
   mock HTML) não simula rolagem lateral entre cartões; só o oficial
   (`preview_meta_oficial`, Task 14, via `generatepreviews`) renderiza o
   carrossel de verdade. Ad format sugerido: `MOBILE_FEED_STANDARD` (cobre a
   rolagem lateral no feed).

6. **Criação (Passo 10) — sempre PAUSED (regra 1) + manifest + rollback.**
   Payload — **testado ao vivo (Task 16), aceito verbatim, zero correção de
   sintaxe**:

   ```json
   {
     "name": "<nome gerado via nomenclatura>",
     "object_story_spec": {
       "page_id": "<page_id>",
       "link_data": {
         "message": "<legenda do carrossel>",
         "link": "<link principal, com UTM dinâmico>",
         "child_attachments": [
           {"link": "<link cartão 1, com UTM dinâmico>", "image_hash": "<hash 1>", "name": "<headline 1>", "description": "<descrição 1>"},
           {"link": "<link cartão 2, com UTM dinâmico>", "image_hash": "<hash 2>", "name": "<headline 2>", "description": "<descrição 2>"}
         ],
         "multi_share_optimized": true,
         "multi_share_end_card": false
       }
     }
   }
   ```

   - `multi_share_optimized` — *"automatically select and order images and
     links. Default is true"* ([doc oficial](https://developers.facebook.com/docs/marketing-api/reference/ad-creative-link-data/)).
     Deixa a Meta reordenar os cartões conforme performance.
   - `multi_share_end_card` — *"If set to false, removes the end card which
     displays the page icon. Default is true"* (mesma doc). `false` = sem
     cartão final "veja a página"; `true` (default, se omitido) mantém.
   - `POST {ad_account}/adcreatives` → `id` do creative. Depois, ad normal com
     `creative.creative_id` (igual aos outros modos).
   - Registra em manifest (`manifest_add "adcreative" "$creative_id"`) e no ad
     — `rollback_on_failure` cobre o Carrossel sem mudança: é 1 creative + 1 ad,
     mesma topologia do Normal single-ad.

### Passo 5 — Coletar criativos

Pergunta path(s) ou pasta:

```
Onde estão os criativos?
  [1] Lista de paths (separados por vírgula)
  [2] Pasta (todos os .jpg/.png/.mp4 dela)
  [3] Download de URLs
```

Detecta automático:
- Extensão: `jpg|jpeg|png|webp` = imagem; `mp4|mov|m4v` = vídeo
- Dimensão: `_detect_image_dims` (sips -g ou identify)
- Spec por posicionamento (feed 1080×1080, stories/reels 1080×1920)

Se fora de spec (resolução insuficiente):

```
⚠ Imagem 500×500 — mínimo pra feed é 1080×1080.
Quer que eu redimensione automaticamente? [s/N]
```

Se sim → `resize_if_needed` (sips no macOS, ImageMagick no Linux/WSL).

**Se fora de spec por aspect ratio, não por resolução (Task 15):** quando a imagem já
tem resolução suficiente mas o aspect ratio nativo diverge do alvo do placement (ex.:
retrato 1080×1920 pra um placement 1:1 de feed, ou uma foto 1200×800 landscape pra
1:1/9:16), resize sozinho distorce (stretch) ou faz letterbox. Oferece crop explícito
como alternativa:

```
⚠ Imagem 1080×1920 (9:16) não bate com o alvo 1:1 (feed).

[r] Redimensionar (resize/stretch pro alvo — pode distorcer)
[c] Crop explícito (corta uma janela 1:1 centrada — sem distorcer, perde borda)
[n] Manter como está (deixa a Meta aplicar o crop automático dela)

Escolha [r/c/n]:
```

Se `[c]`:
1. Calcula a janela centrada pro aspect alvo a partir de `_detect_image_dims`
   (largura×altura originais):
   - Alvo mais estreito/quadrado que a original → corta os lados: `nova_largura =
     altura_original × aspect_alvo`; `margem_x = (largura_original − nova_largura) / 2`;
     janela = `[[margem_x, 0], [margem_x + nova_largura, altura_original]]`.
   - Alvo mais largo que a original → corta topo/base: `nova_altura = largura_original
     ÷ aspect_alvo`; `margem_y = (altura_original − nova_altura) / 2`; janela =
     `[[0, margem_y], [largura_original, margem_y + nova_altura]]`.
   - Exemplo real (testado ao vivo, Task 15 — `tests/20-criativo-avancado.sh
     test_02_image_crops`): fixture 1080×1920 → alvo 1:1 → `margem_y = (1920−1080)/2 =
     420` → janela `[[0,420],[1080,1500]]`.
2. Monta `image_crops` — chave é o aspect ratio alvo no formato `"WxH"` (ex.:
   `"100x100"` = 1:1, **testado ao vivo**; outras razões seguem a mesma convenção da
   [doc oficial de crops](https://developers.facebook.com/documentation/ads-commerce/marketing-api/image-crops),
   mas não foram testadas nesta task — `[não verificado]`).

   ⚠ **Divergência achada ao vivo (Task 15):** `image_crops` **não** funciona como
   campo top-level do creative — a Meta aceita o POST (retorna 201 com `id`), mas
   ignora o campo em silêncio (o GET seguinte devolve objeto vazio, sem erro). Só
   persiste **aninhado dentro de `object_story_spec.link_data.image_crops`**:

   ```json
   {
     "object_story_spec": {
       "page_id": "...",
       "link_data": {
         "image_hash": "...",
         "link": "...",
         "message": "...",
         "image_crops": {"100x100": [[0, 420], [1080, 1500]]}
       }
     }
   }
   ```

   Depois de persistido, o GET espelha o valor tanto em `image_crops` (campo
   top-level, read-only) quanto dentro de `object_story_spec.link_data.image_crops`.
   Ver apêndice em `docs/spikes/2026-07-api-version.md`.

### Passo 6 — Geração de copy (opcional, granular)

```
Quer que eu gere variações de copy baseado no criativo?

Escolha quais campos:
[T]   só Títulos (headline, 27-40 chars)
[D]   só Descrições (27 chars)
[L]   só Legendas (primary text, 125+ chars)
[TD]  Títulos + Descrições
[TDL] Tudo (títulos + descrições + legendas)
[N]   Nada, eu coloco as minhas

Quantas variações por campo? (2-5) [default 4]:
```

**Detecção de voz da marca:**

```bash
voice_file=""
for f in reference/voz-*.md ~/.claude/skills/voz-*/SKILL.md; do
  [[ -f "$f" ]] && { voice_file="$f"; break; }
done
```

Se encontrou, pergunta `Aplicar voz da marca (${voice_file})? [S/n]`.

**Pipeline de geração:**

Pra cada campo escolhido:
1. `gen_copy <field> <count> <image> <objective> <audience> <voice_file> <product>` — script `lib/copy_generator.sh`
2. `copy_prompt_builder.py` monta prompt multimodal
3. `claude_invoke` usa um dos 3 modos:
   - **Claude Code (default):** signal file `CLAUDE_CODE_INVOKE_SUBAGENT` — orchestrator invoca `Task(subagent_type=general-purpose, prompt=<file>)` e escreve output em `output.json`
   - **API SDK (CI):** `ANTHROPIC_API_KEY` → `lib/_py/claude_invoke_api.py`
   - **Mock (testes):** `META_ADS_COPY_MOCK=1`
4. **Humanizer obrigatório:** `humanize_array` passa cada string pela skill humanizer. 3 fallbacks silenciosos (bypass flag / missing skill / timeout) — nunca bloqueia.

Mostra tabela pra aprovação:

```
┌───┬──────────────────────────────────┬──────────────────────┐
│ # │ Headline                         │ Description          │
├───┼──────────────────────────────────┼──────────────────────┤
│ 1 │ Variação acolhimento             │ Desc 1               │
│ 2 │ Variação benefício               │ Desc 2               │
│ 3 │ Variação urgência                │ Desc 3               │
│ 4 │ Variação social proof            │ Desc 4               │
└───┴──────────────────────────────────┴──────────────────────┘

Qual usa?
  "todas"   = todas (viram asset_feed_spec se Dinâmico / múltiplos ads se Normal cartesiano)
  "1,3"     = só as 1 e 3
  "edito"   = abre editor pra você ajustar
```

### Passo 7 — Upload de mídia

- **Imagem:** `upload_image` (multipart `-F source=@file`) → `image_hash`
- **Vídeo:** `upload_video`
  - ≤100MB: direct upload
  - >100MB: resumable (start/transfer/finish)
  - >200MB: resumable + sleep 30s entre chunks (rate limit cputime — erro 17)
  - Polling status=ready timeout 2min
- **Cache por SHA256(file) + post_id em manifest** — fix bug #5

Pra cada arquivo retorna `image_hash` (32 hex) ou `video_id` (numeric).

### Passo 7.5 — Aplicar UTM dinâmico (OBRIGATÓRIO em link externo)

Antes do preview, injeta UTM em todo `link_url` que aponta pra URL `http(s)://` (site/landing).
Pula deeplinks (`wa.me/`, `fb-messenger://`, `tel:`, `mailto:`) — Meta não substitui macros nesses.

```bash
source "$CLAUDE_PLUGIN_ROOT/lib/utm.sh"

# Pra cada link_url coletado nos passos anteriores
if is_external_url "$link_url"; then
  link_url=$(build_utm_url_dynamic "$link_url")
fi
```

Padrão aplicado (mesma macro da skill `nomenclatura-utm`):

```
?utm_source={{site_source_name}}&utm_medium=trafego-pago&utm_campaign={{campaign.name}}&utm_term={{adset.name}}&utm_content={{ad.name}}
```

Aplica em:
- **Normal:** `object_story_spec.link_data.link` (cada ad)
- **Dinâmico:** `asset_feed_spec.link_urls[].website_url` (cada variação de link)
- **Dark post fallback:** `link` do post unpublished

Mostra ao usuário no preview: `🔗 Link com UTM: <url completa>` — confirma transparente.

Se já tiver UTM na URL base, `strip_existing_utm` remove antes de re-aplicar (evita duplicar).

### Passo 8 — Preview visual

ASCII tree default (inline, rápido):

```
┌─ PREVIEW AD #1 ──────────────────────────────────────────┐
│ Nome: image_sorriso_acolhimento_v1
│ Formato: feed
│ Headline: "Paciente Modelo — Belém"
│ Primary:  "Vagas abertas pra quem tá pensando..."
│ Desc:     "Vagas limitadas"
│ CTA: SIGN_UP
│ Destino: Lead Form {form_id}
└──────────────────────────────────────────────────────────┘
```

Depois do ASCII, pergunta qual preview visual (se algum):

```
Preview visual?
  [n] Nenhum, seguir (default)
  [p] Local (HTML mock) — rápido, offline, aproximado
  [o] Oficial Meta (generatepreviews) — fiel ao anúncio real, requer chamada à API

Escolha [n/p/o]:
```

- `[p]` Local: `preview_html` (via `lib/_py/preview_html.py` stdin-safe) gera HTML 375×812 mock, `open`/`xdg-open`/`cmd.exe start` conforme OS. Instantâneo, offline, mas é aproximação — não reflete 100% do que a Meta vai renderizar.
- `[o]` Oficial: `preview_meta_oficial <creative_spec>` (`lib/visual-preview.sh`, Task 14) chama `generatepreviews` de verdade e monta HTML com o(s) iframe(s) oficiais da Meta — um `<h2>` por `ad_format` (ex.: `MOBILE_FEED_STANDARD` pra Normal, `INSTAGRAM_STANDARD`/`INSTAGRAM_STORY`/`INSTAGRAM_REELS` conforme posicionamento escolhido). Mais fiel, mas custa 1 chamada GET por formato — não usar em loop apertado.

### Passo 9 — Confirmação explícita

```
Confirma criação de N ad(s)? [s/n/p=preview local/o=preview oficial] [s]:
```

- `s` → vai pro passo 10
- `n` → cancela (nada criado ainda, rollback não necessário)
- `p` → gera HTML local (mock), abre browser, volta a perguntar
- `o` → gera HTML com preview oficial Meta (`preview_meta_oficial`), abre browser, volta a perguntar

### Passo 10 — Criação (diverge em 2 caminhos por app mode)

**Se `FALLBACK_DARK_POST=true` (app em dev mode — FIX BUG #3):**

Pra cada combo (imagem/vídeo + copy) em Normal, OU uma única vez em Dinâmico:
1. `upload_dark_post <file> <caption> <page_id>` → `post_id`
   (foto unpublished em `/{page}/photos` + post unpublished em `/{page}/feed`)
2. Creative com `object_story_id: post_id` + `call_to_action.value.lead_gen_form_id` (se lead form)
3. Ad com `creative.creative_id`
4. Registra tudo em manifest (dark_post, creative, ad)

**Se Live mode (default):**

1. Creative direto com `object_story_spec` + `image_hash`/`video_id` + CTA + instagram_user_id
2. Ad com creative_id
3. Registra em manifest

**Se Dinâmico (ambos modos):**

1 único creative com `asset_feed_spec`:

```json
{
  "name": "<nome gerado via nomenclatura>",
  "object_story_spec": {"page_id": "...", "instagram_user_id": "..."},
  "asset_feed_spec": {
    "images": [{"hash": "h1"}, {"hash": "h2"}, {"hash": "h3"}],
    "titles": [{"text": "t1"}, {"text": "t2"}],
    "bodies": [{"text": "b1"}, {"text": "b2"}],
    "descriptions": [{"text": "d1"}],
    "call_to_action_types": ["SIGN_UP"],
    "ad_formats": ["SINGLE_IMAGE"]
  }
}
```

**Nunca** cria N×M ads em Dinâmico. Asset feed já combina automaticamente.

**Se Carrossel (ambos app modes):** 1 único creative com
`object_story_spec.link_data.child_attachments` — payload completo, decisão de
hash reusado vs. uploads distintos, e UTM por cartão na seção **Modo
Carrossel** (acima, entre Passo 4 e Passo 5).

#### Placement customization (Task 15, só em modo Dinâmico)

Pergunta adicional, depois de montar o `asset_feed_spec` base:

```
Imagens diferentes por posicionamento? [s/N]
```

Se `s`:
1. Coleta pares imagem ↔ grupo de placements (ex.: "imagem A → feed", "imagem B →
   story"). Um grupo = combinação de `publisher_platforms` + `*_positions` por
   plataforma (`facebook_positions`, `instagram_positions` — testados ao vivo;
   `audience_network_positions`/`messenger_positions` seguem a mesma convenção mas
   **não foram testados** nesta task, `[não verificado]`).
2. **Regra inviolável:** toda imagem referenciada numa `asset_customization_rules`
   precisa do `adlabel` correspondente em `asset_feed_spec.images[].adlabels` (mesmo
   `name` usado em `image_label.name` da rule). Sem o adlabel casando, a rule não tem
   imagem pra apontar.
3. Monta `asset_feed_spec.asset_customization_rules`. Payload de referência —
   **testado ao vivo (Task 15), aceito verbatim, zero correção de sintaxe**:

```json
{
  "name": "<nome gerado via nomenclatura>",
  "object_story_spec": {"page_id": "..."},
  "asset_feed_spec": {
    "images": [
      {"hash": "h1", "adlabels": [{"name": "img_feed"}]},
      {"hash": "h2", "adlabels": [{"name": "img_story"}]}
    ],
    "bodies": [{"text": "corpo"}],
    "titles": [{"text": "titulo"}],
    "link_urls": [{"website_url": "https://..."}],
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

- A Meta devolve o `asset_feed_spec` com campos extras auto-preenchidos por ela
  (`priority` incremental em cada rule, `age_min`/`age_max` dentro de cada
  `customization_spec`, `optimization_type: "PLACEMENT"`) — **não enviar** esses
  campos no payload, são só enriquecimento no round-trip do GET.
- `image_label` referencia o adlabel pelo `name` (não pelo `hash` da imagem
  diretamente) — é por isso que todo par imagem↔placement passa por um adlabel.

### Passo 11 — Resumo + links

```
🚀 3 ads criados (PAUSED)

┌───┬─────────────────────────────────────────┬─────────────────┐
│ # │ Nome                                    │ ID              │
├───┼─────────────────────────────────────────┼─────────────────┤
│ 1 │ image_cadeira_acolhimento_v1            │ 6926427662825   │
│ 2 │ image_sorriso_beneficio_v1              │ 6926427682425   │
│ 3 │ image_close_urgencia_v1                 │ 6926427692125   │
└───┴─────────────────────────────────────────┴─────────────────┘

🔗 Ads Manager:
https://adsmanager.facebook.com/adsmanager/manage/ads?act=<account>&selected_ad_ids=<ids>

🔗 Previews live:
https://www.facebook.com/ads/preview/?id=6926427662825&access_token=...

Quer ativar? [s/n]
```

### Passo 12 — Ativação (só se confirmado)

Se `s`:
- `POST /{campaign_id} {"status":"ACTIVE"}`
- `POST /{adset_id} {"status":"ACTIVE"}`
- `POST /{ad_id} {"status":"ACTIVE"}` para cada ad

Em qualquer falha, rollback reverte tudo na topologia correta (ads → creatives → dark posts).

## Regras invioláveis

1. **Sempre PAUSED na criação** — nunca ACTIVE sem confirmação explícita no passo 12
2. **Sempre humanizer** em copy gerada por IA (pipeline tem 3 fallbacks, zero bloqueio)
3. **Nunca reusar `media_fbid` entre posts diferentes** — cache composto (sha + post_id) garante isso
4. **Rollback automático** se qualquer passo 7-10 falhar (via `rollback_on_failure`)
5. **Asset feed obrigatório em Dinâmico** — produto cartesiano proibido nesse modo
6. **Produto cartesiano em Normal** só com flag `--cartesian` **E** confirmação explícita do usuário
7. **Upload multipart** (`-F source=@file`) — nunca `base64 -i` (BSD-only, quebra em Linux)
8. **Sempre UTM dinâmico em link externo** (passo 7.5) — `build_utm_url_dynamic` via `lib/utm.sh`. Padrão: `utm_source={{site_source_name}}&utm_medium=trafego-pago&utm_campaign={{campaign.name}}&utm_term={{adset.name}}&utm_content={{ad.name}}`. Pula deeplinks (`wa.me`, `messenger://`, `tel:`).

## Limites Graph API v25.0 (referência)

| Objeto | Limite |
|--------|--------|
| Imagens em `asset_feed_spec` | 10 |
| Vídeos em `asset_feed_spec` | 1 (não mistura com images) |
| `titles`/`descriptions`/`bodies` | 5 cada |
| `call_to_action_types` em `asset_feed_spec` | 5 |
| `child_attachments` (Carrossel) | 2–10 (recomendado ≥3 pra performance) |
| Tamanho imagem | 30MB |
| Tamanho vídeo | 4GB |
| Duração vídeo feed | 241min |
| Duração vídeo stories/reels | 60s |
| Direct upload vídeo | ≤100MB |
| Resumable vídeo obrigatório | >100MB |

## Erros catalogados

Ver `lib/error-catalog.yaml` e `lib/error-resolver.sh`:

| Code/Subcode | Causa | Fix |
|--------------|-------|-----|
| 100/1885183 | App em dev mode, `object_story_spec` bloqueado | `switch_to_dark_post_flow` (automático) |
| 100/2654 | Criativo fora das specs de imagem | `offer_sips_resize` + retry |
| 100/1487390 | Vídeo ainda processando (não ready) | Poll status + retry |
| 100/2635 | Formato inválido | User action (troca arquivo) |
| 36007 | Upload de imagem falhou | Retry multipart direto |
| 17/2446079 | BUC rate limit (cputime/call/total_time) | `read_buc_header_and_wait` (implementa CP3b) |
| 100/1815362 | `media_fbid` já em uso | `regenerate_media_fbid` (sobe de novo) |

## Dependências de libs

- `lib/graph_api.sh` — wrapper POST/GET/DELETE com retry + error-resolver
- `lib/upload_media.sh` — upload_image, upload_dark_post, resize_if_needed, media_cache
- `lib/upload_video.sh` — 3 estratégias por tamanho
- `lib/copy_generator.sh` — gen_copy (invoca copy_prompt_builder + claude_invoke_api)
- `lib/humanizer-bridge.sh` — humanize_text, humanize_array com 3 fallbacks
- `lib/utm.sh` — build_utm_url_dynamic, build_utm_url_static, is_external_url, strip_existing_utm (passo 7.5 e Modo Carrossel)
- `lib/error-resolver.sh` — switch_to_dark_post_flow (fix bug #3)
- `lib/rollback.sh` — rollback_on_failure automático
- `lib/visual-preview.sh` — preview_ascii, preview_html (stdin-safe), preview_meta_oficial (iframe oficial via generatepreviews, Task 14)
- `lib/nomenclatura.sh` — gen_name pra criativos (suporta `{nome-criativo}` com hífen)

## Flags CLI

| Flag | Efeito |
|------|--------|
| `--cartesian` | Skip warn, cria N×M ads em Normal |
| `--skip-humanizer` | Bypass skill humanizer (equivale a `META_ADS_SKIP_HUMANIZER=1`) |
| `--dry-run` | Não faz POST, escreve ghost manifest em `dry-runs/` |
| `--dark-post` | Força dark post flow mesmo em live mode (útil pra preview aberto) |
