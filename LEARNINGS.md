# LEARNINGS — meta-ads-pro

Esse arquivo documenta decisões, bugs, fixes e trade-offs que emergiram durante o
desenvolvimento. Atualizado a cada CP. Release final: **v1.0.0 — 2026-04-21**.

---

## Resumo final v1.0.0

### Os 10 bugs do caso Filipe — origem + solução permanente

Esses bugs foram descobertos num caso real de lançamento com o Filipe (infoprodutor,
campanha de formulário no Instagram). Cada um virou um `test_bug_NN_*` em
`tests/00-regression-filipe.sh` — regressão permanente, nunca mais volta.

| # | Sintoma | Origem | Fix permanente |
|---|---------|--------|----------------|
| 1 | Erro 100/1870227 em POST de campanha ABO | Meta exige `is_adset_budget_sharing_enabled: false` explícito pra ABO | `lib/graph_api.sh` envia o flag em todo POST de campanha ABO. Test: `test_bug_01_ABO_budget_sharing_flag` |
| 2 | Erro 100/1885183 em POST de ad set | `targeting.targeting_automation.advantage_audience` ausente | Payload padrão do conjuntos sempre inclui o campo com valor `0`. Test: `test_bug_02_advantage_audience` |
| 3 | `object_story_spec` bloqueado em dev mode | App Meta em dev mode rejeita page posts via API | `check_app_mode` no doctor → seta `FALLBACK_DARK_POST=true` → anúncios usam `/page_id/feed` (dark post). Transparente pro user. Test: `test_bug_03_dev_mode_detection` |
| 4 | Dinâmico criando 15 ads em vez de 1 | Plano anterior fazia produto cartesiano no client | `skills/anuncios/` emite **1 ad com `asset_feed_spec`** — Meta combina. Test: `test_bug_04_no_cartesian_in_dynamic` |
| 5 | `media_fbid` reusado entre posts diferentes | Cache key só usava hash do arquivo | Cache composto `sha256(file) + post_id`. Test: `test_bug_05_media_fbid_hygiene` |
| 6 | Nomenclatura hardcoded (`[FORMULARIO][X][AUTO]` não funcionava) | Placeholder system inexistente | `lib/nomenclatura.sh` + templates customizáveis em `CLAUDE.md` com regex `[a-zA-Z-]*` cobrindo hífen |
| 7 | Privacy URL do Instagram aceita no form | Validação só checava HTTP 200 | `lib/privacy-validator.sh` — 3 camadas (HEAD, fetch com UA, keyword match PT+EN), rejeita domínios `instagram.com`. Test: `test_bug_07_privacy_policy_instagram` |
| 8 | Lead form sem `disqualified_thank_you_page` | Cliente-side não validava | Skill `lead-forms/` bloqueia POST sem as duas thank you pages. Test: `test_bug_08_lead_form_thankyou_duo` |
| 9 | Sem rollback quando falhava mid-run | Não existia manifest de run | `lib/rollback.sh` + `lib/_py/manifest.py` — topológico, idempotente, retry em 613/80004 |
| 10 | Sem preflight antes de POST | Usuário descobria erros só no 4º passo | `/meta-ads-doctor --silent` roda como preflight interno. 10 checks. Test: `test_bug_10_preflight_doctor` |

### Arquitetura final

```
meta-ads-pro/
├── .claude-plugin/plugin.json         # manifest v1.0.0
├── install.sh / uninstall.sh          # bash 3.2+ portable
├── commands/                          # 13 slash commands (thin wrappers)
│   ├── meta-ads.md                    # orquestradora
│   ├── meta-ads-setup.md
│   ├── meta-ads-doctor.md
│   ├── meta-ads-campanha.md
│   ├── meta-ads-conjuntos.md
│   ├── meta-ads-anuncios.md
│   ├── meta-ads-lead-forms.md
│   ├── meta-ads-publicos.md
│   ├── meta-ads-regras.md
│   ├── meta-ads-insights.md
│   ├── meta-ads-import-existing.md
│   ├── meta-ads-rollback.md
│   ├── meta-ads-update.md
│   └── meta-ads-analyze-telemetry.md
├── skills/                            # 10 sub-skills (SKILL.md + fluxo)
│   ├── orquestradora/
│   ├── setup/  doctor/  campanha/  conjuntos/
│   ├── anuncios/  lead-forms/
│   ├── publicos/  regras/  insights/
│   └── import-existing/
├── lib/                               # 16 helpers shell
│   ├── graph_api.sh                   # wrapper HTTP + retry + DRY_RUN + error-resolver
│   ├── preflight.sh                   # 10 checks do doctor
│   ├── nomenclatura.sh                # templates + placeholders
│   ├── rollback.sh                    # topológico, idempotente
│   ├── upload_media.sh / upload_video.sh   # multipart cross-platform, 3 estratégias
│   ├── copy_generator.sh              # IA T/D/L/TD/TDL
│   ├── humanizer-bridge.sh            # 3 fallbacks, nunca bloqueia
│   ├── error-resolver.sh              # catalog + WebSearch + auto-learning
│   ├── error-catalog.yaml             # padrões conhecidos
│   ├── privacy-validator.sh           # 3 camadas bilíngue + cache 24h
│   ├── visual-preview.sh              # ASCII + HTML
│   ├── preview-templates/             # HTML templates por placement
│   ├── lockfile.sh / telemetry.sh / feature_flags.sh / banner.sh
├── lib/_py/                           # 15 scripts Python standalone
│   ├── manifest.py                    # serializer + PRIORITY topológica
│   ├── media_hash.py                  # sha256(file) + post_id
│   ├── copy_prompt_builder.py         # prompt builder
│   ├── claude_invoke_api.py           # Anthropic SDK fallback
│   ├── dry_run_manifest.py            # ghost entries
│   ├── import_existing.py             # paginação cursor + redact
│   ├── preview_ascii.py / preview_html.py
│   ├── privacy_check.py
│   ├── telemetry_log.py / analyze_telemetry.py
│   ├── feature_flags_get.py
│   ├── detect_pattern.py / log_unknown_error.py
│   └── leads_to_csv.py
└── tests/                             # 14 suítes + cleanup + run_all
    ├── 00-regression-filipe.sh        # 10 bugs — regressão permanente
    ├── 01-lint.sh                     # shellcheck zero warnings
    ├── 02-components.sh               # unit libs (87+ testes)
    ├── 04-doctor.sh  05-campanha-crud.sh  06-conjuntos-targeting.sh
    ├── 07-anuncios-upload.sh  08-lead-forms.sh  09-publicos.sh
    ├── 10-regras.sh  11-insights.sh
    ├── 12-import-existing.sh  13-dry-run.sh
    ├── 14-integracao.sh  15-e2e.sh  16-stress.sh
    ├── cleanup.sh / run_all.sh / fixtures/ reports/
```

### Performance do time — CP1 → CP4

| Métrica | Valor |
|---------|-------|
| Agents spawned | **9 únicos** entre CP1-CP3 (bash-dev, python-dev, test-dev, docs-dev, reviewer-opus + specialists) |
| Model mix | Maioria **opus** (coding + review); sonnet/haiku só em tasks triviais de docs |
| Wall-time CP1 | ~40 min (21 tasks, 7 commits) |
| Wall-time total CP1-CP4 | ~3-4h distribuído |
| Commits totais | 49 commits na `feature/cp4-release` |
| Testes automatizados | 146+ (295 chamadas de teste distribuídas em 14 arquivos) |
| Bugs do plano corrigidos durante implementação | 1 real (str(False)) + 4 compat macOS |
| Bugs do caso Filipe fixados com regression test | **10/10** |

### Decisões arquiteturais validadas

- **`lib/_py/` pra scripts Python standalone** — zero bugs de escape/heredoc em toda
  a codebase Python; todo shell fino delega via subprocess
- **shellcheck zero warnings** — obrigatório nos 16 shell libs
- **bash 3.2 first-class** — sem `mapfile`, sem `declare -A` inline, sem GNU-only sed;
  testado em macOS 3.2.57
- **Topologia de rollback em Python dict** — mais fácil de testar + cross-platform
- **Preflight via `/meta-ads-doctor --silent`** — uma só fonte de verdade pra
  "ambiente tá OK" (fix bug #10 gera value em todos os outros fluxos)
- **`asset_feed_spec` pra Dinâmico** — deixa Meta combinar (vs produto cartesiano
  client-side que explodia ads count)

### Commits consolidados v1.0.0-cp1 → v1.0.0

Branch `feature/cp4-release`, 49 commits agrupados:

- **CP1 (Foundation)** — 7 commits (scaffold + libs + preflight + lint compat)
- **CP2 (Core operacional)** — 20 commits (campanha + conjuntos + anúncios +
  copy generator + humanizer bridge + upload cross-platform + media_hash +
  error-resolver + dark post fallback + asset_feed_spec)
- **CP3 (Features avançadas)** — 14 commits (lead-forms + privacy-validator +
  import-existing + orquestradora + analyze-telemetry + testes e2e + stress)
- **CP4 (Release)** — docs README + CHANGELOG + LEARNINGS + install/uninstall +
  tag v1.0.0

Tags:
- `v1.0.0-alpha.1` — 2026-04-21 (scaffold inicial)
- `v1.0.0` — 2026-04-21 (release final com 10 bugs fixados)

---

## CP1 — Foundation (2026-04-21)

### Bugs do plano detectados e corrigidos durante implementação

**1. `str(False)` → `"False"` em JSON payload (error-resolver.sh)**
- Plano tinha: `fix_args: [false]` e no bash `python3 -c "print(str(value))"` retornava `"False"` capitalized.
- Meta Graph API rejeita `"False"` — precisa ser `false` lowercase.
- Fix: bash-dev adicionou função `fmt_arg()` que normaliza bool→lowercase antes de embutir no payload.

**2. `declare -A` inline não funciona em bash 3.2 (macOS default)**
- Plano usava `declare -A ROLLBACK_PRIORITY=([ad]=1 ...)`.
- bash 3.2 (que é o default do macOS) não aceita inline values em associative arrays.
- Fix: removido `declare -A` do `lib/rollback.sh` — lógica de PRIORITY está no `lib/_py/manifest.py` (`PRIORITY` dict), shell só delega via subprocess.

**3. BSD sed incompatibilidade (nomenclatura.sh)**
- Plano usava `sed 's/_\{[a-z]*\}//g'` — sintaxe GNU sed.
- macOS usa BSD sed, trata `\{` como literal braces.
- Fix: `sed 's/_[{][a-zA-Z]*[}]//g'` — char classes `[{]`/`[}]` funcionam em BRE+ERE de ambos dialects. Portável.

**4. `mapfile` em `tests/01-lint.sh` (bash 4+, quebra em macOS bash 3.2)**
- `mapfile -t sh_files < <(find ...)` é bash 4+; macOS default é 3.2.57.
- shellcheck não flagga versioning, passou no review do bash-dev. Pego no cross-cutting review.
- Fix: substituir por `while IFS= read -r f; do arr+=("$f"); done < <(find ...)` — portable.
- Cascade: `run_all.sh` tem `|| exit 1` na camada 1 → quebra a camada 2 também.
- Commit fix: `f76e816`.

**4. Docstring inconsistente em detect_pattern.py (plano)**
- Docstring do plano dizia uma coisa, código fazia outra.
- python-dev detectou durante implementação e corrigiu a docstring pra bater com o comportamento.

---

### Follow-ups registrados pela review (CP2+)

**FU-1 — `visual-preview.sh` heredoc injection risk**
- `python3 - <<PYEOF ... json.loads('''$payload''')` é vulnerável se `$payload` contiver `'''` em campos user-controlled.
- CP1: risco baixo (payload construído pelo próprio código).
- CP2+: vira **Critical** quando lead form labels e ad text vierem do usuário.
- **Fix:** refatorar pra passar payload via `stdin` ou `argv` (pattern já usado em `lib/_py/log_unknown_error.py`).
- Scope: antes do CP2c (anúncios). **Resolvido no commit `5f4ec50`.**

**FU-2 — `nomenclatura.sh` regex não cobre hífen**
- Regex `[a-zA-Z]*` não casa placeholders com hífen tipo `{nome-criativo}`.
- Placeholder não stripado se user não preencher.
- **Fix:** `[a-zA-Z-]*` ou `[a-zA-Z][a-zA-Z-]*`.
- Scope: CP2c (primeiro uso de `{nome-criativo}`). **Resolvido em `5f4ec50`.**

**FU-3 — `feature_flags.sh` mesmo pattern heredoc**
- Mesma vulnerabilidade do FU-1, severidade menor (flag name é config interna, não user-controlled).
- **Fix:** junto com FU-1. **Resolvido em `5f4ec50`.**

**FU-4 — `preview_and_confirm` perdeu parameterization**
- Plano tinha `preview_and_confirm <level> <preview_fn> <payload>` pra extensibilidade.
- bash-dev hardcodou `preview_html_campaign` — funciona pra CP1 (só campaign).
- **Fix:** re-introduzir `preview_fn` parameter quando adset/ad/leadform previews chegarem no CP2.
- Scope: CP2a (campanha concluída). **Resolvido em `5f4ec50`.**

---

### Minor notes do cross-cutting review (CP2)

**M1 — `check_app_mode` branch inconclusive sem fail-safe**
- Quando a resposta da Graph API é ambígua (nem erro 1885183 nem creative_id), função retorna 1 mas deixa `FALLBACK_DARK_POST` unset.
- Edge case raro, mas pode bugar fluxos de CP2 que checam a flag.
- **Fix sugerido:** defaulting pra `FALLBACK_DARK_POST=true` (mais seguro — dark post sempre funciona).
- Scope: quick patch no início do CP2.

**M2 — curl direto em `check_token_expiration`/`check_scopes`**
- Bypassa o wrapper `lib/graph_api.sh` (perde retry em 5xx).
- Justificável: `debug_token` endpoint usa schema de auth diferente (`input_token=X&access_token=Y`).
- Aceitável. Se quiser normalizar, adicionar suporte a "two-token" no `graph_api`.

**M3 — `jq ... || echo 0` silencia erros de syntax**
- `check_learnings` usa fallback gentil pra contar entries em `unknown_errors.jsonl`.
- Se JSONL tiver syntax error, silencia com 0.
- Aceitável pra CP1; se CP2 precisar diagnóstico preciso, trocar pra validação explícita.

---

### Decisões arquiteturais validadas

- **lib/_py/ pra scripts Python standalone** — pagou dividendos: todos os scripts Python passaram review sem bug de escape/heredoc hell (zero issues de injection), diferente do pattern rejeitado no review round 1.
- **shellcheck zero warnings** — obrigatório; bash-dev manteve em todos os 10 scripts.
- **Testes granulares em `02-components.sh`** — 16 testes rodando em ~2s, catch de regressão imediato.
- **Topologia de rollback com priority dict no Python** — mais fácil testar + cross-platform.

### Performance do time

- 5 agents spawnados (bash-dev, python-dev, test-dev, docs-dev sonnet/haiku + reviewer opus)
- 21 tasks em ~40 minutos wall-time
- 7 commits no git
- 16 testes automatizados passando
- 1 bug real do plano fixado (str(False)), 4 bugs de compatibilidade macOS corrigidos (BSD sed, bash 3.2 `declare -A`, `mapfile`, inconsistências)
- Issues de coordenação: bash-dev marcou tasks como completed sem commitar inicialmente → corrigido via intervenção do team-lead

### Commits finais CP1

```
f76e816 fix(tests): 01-lint.sh usa while read em vez de mapfile (bash 3.2 compat)
5b27942 docs: LEARNINGS.md com bugs/fixes + 4 follow-ups do review CP1
bea7afc feat(lib): preflight.sh com 10 checks do doctor
78edd0d chore: scaffold inicial + todos os lib helpers CP1
72721c3 chore: scaffold inicial meta-ads-pro v1.0.0-alpha.1
52ccf5d feat(_py): 4 scripts standalone (telemetry_log, manifest, log_unknown_error, detect_pattern)
22b0700 feat(docs): skills setup + doctor com 11 passos + 10 checks
```

---

## CP2 — Core operacional (2026-04-21)

### Entregas

- Skills `campanha/`, `conjuntos/`, `anuncios/` completas com SKILL.md + commands
- Fix dos bugs **#1, #2, #3, #4, #5** (regression tests em `00-regression-filipe.sh`)
- `lib/upload_media.sh` + `lib/upload_video.sh` cross-platform (3 estratégias: direct ≤100MB, resumable >100MB, sleep 30s >200MB)
- `lib/copy_generator.sh` com 3 modos (Claude Code signal file, Anthropic SDK, mock)
- `lib/humanizer-bridge.sh` com 3 fallbacks (skill → SDK → passthrough)
- `lib/error-resolver.sh` com apply-retry loop pro fix automático (add_field / add_nested)
- `lib/error-resolver.sh → switch_to_dark_post_flow` (bug #3)
- `lib/_py/`: `media_hash.py`, `copy_prompt_builder.py`, `claude_invoke_api.py`, `dry_run_manifest.py`, `import_existing.py` (estruturais)
- `lib/graph_api.sh` ganhou `META_ADS_DRY_RUN` wire (intercepta POST/DELETE)
- Testes 05-07, 13-14 cobrindo CRUD + dry-run + integração

### Follow-ups resolvidos
- FU-1/FU-2/FU-3/FU-4 do CP1 — commit `5f4ec50`
- Review round 1 minors M1-M4 (_py) — commit `63c8f55`
- SC2155 em humanizer-bridge (declare+assign split) — commit `8069c2f`
- Hotfix dry-run wire — commit `d12f11f`

### Commits principais CP2

```
723d969 Merge CP2: Core operacional (campanha+conjuntos+anuncios)
d12f11f fix(graph_api): wire META_ADS_DRY_RUN
8069c2f fix(humanizer-bridge): SC2155
9e8b3fc test(regression): bugs #3/#4/#5
a2f089e test(anuncios): suite 20 testes
f8fc438 feat(anuncios): SKILL.md + command 12 passos
c0c77be feat(error-resolver): switch_to_dark_post_flow
8ab90f3 feat(lib): humanizer-bridge + copy_generator
309c5c2 feat(lib): upload_media cross-platform + upload_video 3 estratégias
5f4ec50 fix(lib): FU-1/FU-2/FU-3/FU-4
51dcc8b test(conjuntos): tests/06-conjuntos-targeting.sh — 15 testes
99c26c8 feat(conjuntos): SKILL + command — 5 destinos + bug #2
f3a78bd test(regression): bug #1 is_adset_budget_sharing_enabled
```

---

## CP3 — Features avançadas (2026-04-21)

### Entregas

- Skill `lead-forms/` com 9 passos + command `meta-ads-lead-forms`
- Fix dos bugs **#7, #8** (regression tests)
- `lib/privacy-validator.sh` — 3 camadas bilíngue PT+EN + cache 24h em `~/.claude/meta-ads-pro/cache/privacy/`
- `lib/_py/analyze_telemetry.py` spec §5.6 (top erros, sub-skills ranking, taxa sucesso, duração)
- `lib/_py/leads_to_csv.py` — export Instant Form leads
- `import-existing/` SKILL + command (GET-only, paginação cursor, token redacted)
- Skill `orquestradora/` (banner + doctor + routing)
- Skills sanitizadas: `publicos/`, `regras/`, `insights/`
- Commands `rollback`, `update`, `analyze-telemetry`
- Testes 08 (lead-forms), 12 (import), 13 (dry-run), 14 (integração), 15 (e2e), 16 (stress)

### Hardening
- Review M1+M2 CP3b: FU-1 compliance em leads_to_csv (stdin, não heredoc) + JSONDecodeError hardening no analyze_telemetry — commit `7eff2d3`

### Commits principais CP3

```
a876d62 Merge CP3: Features avançadas
074d39f feat(cp3): orquestradora + sanitize + integração/E2E
7eff2d3 fix(cp3b): review M1+M2 — FU-1 compliance + JSONDecodeError hardening
3be9d2d feat(_py): leads_to_csv.py + hardening analyze_telemetry
73cd012 feat(import-existing): SKILL.md + command wrapper
fbb199f feat(commands): rollback + update + analyze-telemetry
b0f3500 feat(_py): analyze_telemetry.py — spec §5.6
4e3de6a test(regression): bugs #7 e #8
e62acac test(lead-forms): tests/08-lead-forms.sh — 12 testes
a4b8e1c feat(lead-forms): SKILL 9 passos + command
e5d94ce feat(lib): privacy-validator 3 camadas bilíngue + cache 24h
7c9d74c test(import): tests/12-import-existing.sh
98b1e4b test(dry-run): tests/13-dry-run.sh
```

---

## CP4 — Release (2026-04-21)

### Entregas

- `install.sh` com auto-desinstall da versão antiga + backup + cross-platform deps check
- `uninstall.sh` com wipe opcional de dados runtime
- `README.md` completo (quickstart, 13 commands, 5 exemplos de destino, troubleshooting, contributing, license)
- `CHANGELOG.md` com entry v1.0.0 detalhado (9 sub-skills, 10 bugs fixados com subcode, upgrade path)
- `LEARNINGS.md` final (este arquivo) — resumo dos 4 CPs, arquitetura consolidada, commits
- Tag `v1.0.0` + GitHub Release (via `gh release create`)
