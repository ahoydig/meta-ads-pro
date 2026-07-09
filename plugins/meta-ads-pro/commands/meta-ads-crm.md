---
description: "Pipeline de lead → GHL/FluxiHub: valida integração nativa, checklist de mapeamento de forms, teste ponta-a-ponta com test lead, setup e teste de CAPI do funil."
---

Invoque a skill `meta-ads-pro/crm` seguindo `flows/crm/SKILL.md`.

**Modos:**
- `status` → saúde da integração (GHL alcançável, receiver up, página subscrita em leadgen)
- `mapear {form_id}` → checklist de mapeamento do form no GHL + custom fields de atribuição
- `testar {form_id?}` → cria form `TEST_` novo, dispara test lead, verifica contato na subconta
- `capi-setup` / `capi-testar` → Conversions API do funil (ver Task 12 — stub ainda)

**Libs obrigatórias:**
- `lib/graph_api.sh` — wrapper HTTP com retry + error-resolver + DRY_RUN (chamadas à Meta)
- `ghl_api()` — helper inline do próprio `flows/crm/SKILL.md` (chamadas ao GHL)

**Regras invioláveis:** nunca ecoar `GHL_PIT_TOKEN` nem `META_ACCESS_TOKEN`; test lead só
em form `TEST_` criado por este flow ou com confirmação explícita; `test_leads` tem limite
de 1 por form — sempre form novo por rodada; forms de teste são arquivados (nunca
deletados) com page token.
