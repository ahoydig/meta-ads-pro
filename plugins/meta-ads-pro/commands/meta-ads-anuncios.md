---
description: "Criar anúncios Meta Ads (Normal 1:1 ou Dinâmico asset_feed_spec). Upload multipart cross-platform, dev mode fallback transparente via dark post, cache de media_fbid anti-reuso, geração de copy com humanizer, preview ASCII/HTML."
---

Invoque a skill `meta-ads-pro/anuncios` seguindo o fluxo de 12 passos em `flows/anuncios/SKILL.md`.

**Libs obrigatórias (source na ordem):**
1. `lib/graph_api.sh`
2. `lib/upload_media.sh`
3. `lib/upload_video.sh`
4. `lib/copy_generator.sh`
5. `lib/humanizer-bridge.sh`
6. `lib/error-resolver.sh`
7. `lib/rollback.sh`
8. `lib/visual-preview.sh`
9. `lib/nomenclatura.sh`

**Pré-condições (valida em Passo 1):**
- `CURRENT_RUN_ID` setado (manifest existe)
- `AD_ACCOUNT_ID`, `PAGE_ID`, `INSTAGRAM_USER_ID` disponíveis
- `FALLBACK_DARK_POST` setado (true/false) pelo preflight — se app em dev mode, roteia passo 10 pro dark post flow automaticamente (fix bug #3)
- `CAMPAIGN_ID`, `ADSET_ID` passados (invocação via orquestradora) OU perguntados ao user (invocação direta)

**Regras que NÃO podem ser violadas:**

- Sempre PAUSED na criação (ACTIVE só no passo 12 com confirmação)
- Dinâmico = 1 ad com asset_feed_spec — **nunca** produto cartesiano nesse modo (fix bug #4)
- `media_fbid` nunca reusado entre posts diferentes — cache composto (sha + post_id) (fix bug #5)
- Humanizer aplicado em toda copy gerada por IA (3 fallbacks, zero bloqueio)
- Upload multipart `-F source=@file` (nunca base64)
- Rollback automático em qualquer falha dos passos 7-10

**Signal files pro orchestrator:**

A skill em bash cria signal files que **este orchestrator intercepta e responde**:

1. **`CLAUDE_CODE_INVOKE_SUBAGENT`** (copy generation):
   - Input: `prompt_file` = caminho com o prompt do copy_prompt_builder.py
   - Output esperado: gravar JSON array em `output_file`
   - Ação: invoca `Task(subagent_type=general-purpose, prompt=<cat prompt_file>)` e escreve resposta em `output_file`. Agent retorna JSON array puro (já instruído no prompt).

2. **`CLAUDE_CODE_INVOKE_HUMANIZER`** (pipeline de humanização):
   - Input: `input_file` = texto raw, `voice_file` = path pro voice profile
   - Output esperado: texto humanizado em `output_file`
   - Ação: invoca a skill `humanizer` com o texto de `input_file` e escreve resposta em `output_file`.

Se não rodando dentro do Claude Code, skill usa fallbacks: `META_ADS_COPY_MOCK=1` (testes) ou `ANTHROPIC_API_KEY` (CI via SDK direto).
