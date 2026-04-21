---
description: "Instant Forms CRUD: criar/listar/editar/deletar/export leads. Valida política de privacidade bilíngue PT+EN em 3 camadas, força thank you qualificado+desqualificado (fix bug #8), suporta conditional logic + qualifier/disqualifier (fix bug #7 privacy Instagram)."
---

Invoque a skill `meta-ads-pro/lead-forms` seguindo o fluxo de 9 passos em `skills/lead-forms/SKILL.md`.

**Libs obrigatórias:**
- `lib/graph_api.sh` — wrapper HTTP com retry + error-resolver + DRY_RUN
- `lib/privacy-validator.sh` — validação 3 camadas bilíngue (cache 24h)
- `lib/_py/manifest.py` — registro do form pra rollback
- `lib/rollback.sh` — reverter form criado se o user cancelar

**Modos de execução:**
- (sem argumento) → criação interativa, 9 passos
- `list` → GET `/{page_id}/leadgen_forms`
- `edit {form_id}` → duplica + edita
- `delete {form_id}` → DELETE `/{form_id}`
- `export {form_id}` → leads pra CSV

**Regras invioláveis:**
1. Privacy URL validada antes do POST (bug #7)
2. `thank_you_page` E `disqualified_thank_you_page` obrigatórios client-side (bug #8)
3. Page token, não user token, pra POST `/leadgen_forms`
4. Nunca ecoar `$META_ACCESS_TOKEN`
