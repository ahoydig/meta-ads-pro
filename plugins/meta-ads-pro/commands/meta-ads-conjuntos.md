---
description: "CRUD de ad sets Meta Ads — criar (fluxo 11 passos), listar, editar, pausar/ativar, deletar. 5 destinos (SITE/LEAD_FORM/WHATSAPP/MESSENGER/CALL). Fix bug #2 (advantage_audience). Geocode ViaCEP + Nominatim, dayparting, frequency cap."
---

Invoque a skill `meta-ads-pro/conjuntos` seguindo o fluxo documentado em `flows/conjuntos/SKILL.md`.

Libs: `lib/graph_api.sh`, `lib/nomenclatura.sh`, `lib/rollback.sh`, `lib/telemetry.sh`, `lib/visual-preview.sh`, `lib/preflight.sh`.

Modos:
- `/meta-ads-conjuntos` — fluxo de criação (11 passos)
- `/meta-ads-conjuntos list [campaign_id]`
- `/meta-ads-conjuntos edit {id}`
- `/meta-ads-conjuntos pause {id}`
- `/meta-ads-conjuntos activate {id}`
- `/meta-ads-conjuntos delete {id}` — só se PAUSED

5 destinos suportados: Site externo (`WEBSITE`), Lead Form (`ON_AD`), WhatsApp (`WHATSAPP`), Messenger (`MESSENGER`), Chamada (`PHONE_CALL`).

Payload obrigatório (fix bug #2): `targeting.targeting_automation.advantage_audience: 0` em TODO POST.

Geocoding: `https://viacep.com.br/ws/{cep}/json/` + `https://nominatim.openstreetmap.org/search` (User-Agent obrigatório, rate limit 1 req/s). Fallback pra input manual se offline.
