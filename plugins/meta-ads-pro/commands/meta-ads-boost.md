---
description: "Impulsionar (boost) post ou Reel JÁ PUBLICADO do Instagram como anúncio — preserva curtidas/comentários (social proof), sem dark post. Lista mídia, checa boost_eligibility_info antes de tentar, cria creative (source_instagram_media_id sozinho) + ad PAUSED via adset ON_POST/POST_ENGAGEMENT."
---

Invoque a skill `meta-ads-pro/boost` seguindo o fluxo de 6 passos em `flows/boost/SKILL.md`.

**Libs:** `lib/graph_api.sh`, `lib/nomenclatura.sh`, `lib/rollback.sh`, `lib/preflight.sh`, `lib/visual-preview.sh`.

**Pré-condições (valida em Passo 1):**
- `AD_ACCOUNT_ID`, `PAGE_ID`, `INSTAGRAM_USER_ID` disponíveis (CLAUDE.md/env)
- `instagram_user_id:` presente em `CLAUDE.md` — o doctor genérico (`check_claude_md_config`) não valida esse campo; se ausente, oriente `/meta-ads-setup`

**Payload do creative (fixo, não editar sem reconferir o spike):**

```json
{"name": "{nome via gen_name}", "source_instagram_media_id": "{media_id}"}
```

**Nunca** adicionar `object_story_spec`, `page_id`, `instagram_user_id` ou `instagram_actor_id` nesse payload — todas essas combinações foram testadas ao vivo e quebram (ambiguidade ou ignoradas silenciosamente). Ver `docs/spikes/2026-07-boost-ig.md`, seção 2.

**Payload do ad set de boost (destino não coberto por `/meta-ads-conjuntos`):**

```json
{
  "destination_type": "ON_POST",
  "optimization_goal": "POST_ENGAGEMENT",
  "bid_strategy": "{obrigatório — ex. LOWEST_COST_WITHOUT_CAP}",
  "promoted_object": {"page_id": "{PAGE_ID}"}
}
```

`bid_strategy` ausente quebra com `100/2490487`. Ver spike, seção 3.2.

**Diferença de `/meta-ads-anuncios`:** boost referencia mídia **já publicada** (`source_instagram_media_id`) e preserva curtidas/comentários/permalink do post orgânico; `/meta-ads-anuncios` cria post novo (dark post ou live) a partir de arquivo solto.

**Regras que NÃO podem ser violadas:**
- Sempre PAUSED na criação (ACTIVE só no passo 6 com confirmação)
- Checar `boost_eligibility_info` (GET) antes de qualquer POST de creative
- Falha de elegibilidade em 1 mídia não aborta o lote inteiro
- Nunca UTM dinâmico (destino é o post, sem link externo)
