---
description: "CRUD de campanhas Meta Ads — criar (fluxo 8 passos), listar, editar, pausar, ativar, deletar. Fix bugs #1 (is_adset_budget_sharing_enabled) e #10 (preflight). Suporta 6 objetivos, ABO/CBO, 5 bid strategies."
---

Invoque a skill `meta-ads-pro/campanha` seguindo o fluxo documentado em `flows/campanha/SKILL.md`.

Libs: `lib/graph_api.sh`, `lib/nomenclatura.sh`, `lib/rollback.sh`, `lib/telemetry.sh`, `lib/visual-preview.sh`.

Modos:
- `/meta-ads-campanha` — fluxo de criação (8 passos)
- `/meta-ads-campanha list [active|paused|all]`
- `/meta-ads-campanha edit {id}`
- `/meta-ads-campanha pause {id}`
- `/meta-ads-campanha activate {id}`
- `/meta-ads-campanha delete {id}` — só se PAUSED
