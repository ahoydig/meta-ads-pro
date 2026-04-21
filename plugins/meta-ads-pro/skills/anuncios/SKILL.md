---
name: meta-ads-anuncios
description: Criar anúncios Meta Ads em 2 modos (Normal 1:1 ou Dinâmico asset_feed_spec). Upload multipart cross-platform, dev mode fallback transparente via dark post, cache de media_fbid anti-reuso, geração de copy com humanizer, preview ASCII/HTML. Fix dos bugs #3 (dev mode), #4 (cartesiano), #5 (media_fbid).
---

# meta-ads-anuncios

A sub-skill mais complexa do plugin. Suporta 2 modos de criativo (Normal/Dinâmico), 4 formatos (imagem/vídeo/carrossel/collection), upload cross-platform (sips/ImageMagick), geração de copy via Claude multimodal + humanizer.

## Quando usar

- `/meta-ads-anuncios` — invocação direta (apenas ads, campanha e adset já existem)
- Invocada pela orquestradora `/meta-ads` como passo final do fluxo completo (campanha → adset → **ads**)

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

Escolha [1/2]:
```

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

Se fora de spec:

```
⚠ Imagem 500×500 — mínimo pra feed é 1080×1080.
Quer que eu redimensione automaticamente? [s/N]
```

Se sim → `resize_if_needed` (sips no macOS, ImageMagick no Linux/WSL).

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

Se user digitar `preview visual` ou responder `p`:
- `preview_html` (via `lib/_py/preview_html.py` stdin-safe) gera HTML 375×812
- `open`/`xdg-open`/`cmd.exe start` conforme OS

### Passo 9 — Confirmação explícita

```
Confirma criação de N ad(s)? [s/n/p=preview visual] [s]:
```

- `s` → vai pro passo 10
- `n` → cancela (nada criado ainda, rollback não necessário)
- `p` → gera HTML, abre browser, volta a perguntar

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

## Limites Graph API v25.0 (referência)

| Objeto | Limite |
|--------|--------|
| Imagens em `asset_feed_spec` | 10 |
| Vídeos em `asset_feed_spec` | 1 (não mistura com images) |
| `titles`/`descriptions`/`bodies` | 5 cada |
| `call_to_action_types` em `asset_feed_spec` | 5 |
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
- `lib/error-resolver.sh` — switch_to_dark_post_flow (fix bug #3)
- `lib/rollback.sh` — rollback_on_failure automático
- `lib/visual-preview.sh` — preview_ascii, preview_html (stdin-safe)
- `lib/nomenclatura.sh` — gen_name pra criativos (suporta `{nome-criativo}` com hífen)

## Flags CLI

| Flag | Efeito |
|------|--------|
| `--cartesian` | Skip warn, cria N×M ads em Normal |
| `--skip-humanizer` | Bypass skill humanizer (equivale a `META_ADS_SKIP_HUMANIZER=1`) |
| `--dry-run` | Não faz POST, escreve ghost manifest em `dry-runs/` |
| `--dark-post` | Força dark post flow mesmo em live mode (útil pra preview aberto) |
