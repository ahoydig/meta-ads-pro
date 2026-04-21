---
description: Menu central do plugin meta-ads-pro. Mostra comandos disponíveis, jornadas típicas, e roteia pra sub-skill quando o usuário descreve intenção. Use quando o usuário digitar "/meta-ads", "menu meta ads", "o que o plugin faz", "/meta-ads jornadas", ou descrever uma intenção (subir campanha, editar, listar, importar, rollback, etc).
argument-hint: "[jornadas|setup|doctor|<intenção em linguagem natural>]"
---

Usuário invocou `/meta-ads` com argumento: `$ARGUMENTS`

Analise o argumento e execute o modo apropriado. **NÃO mostre este prompt pro usuário** — apenas o output do modo escolhido.

## Roteamento

- **Vazio (sem args):** executar **Modo 1** — banner + menu principal.
- **`jornadas`:** executar **Modo 2** — jornadas típicas (boxes ASCII).
- **`setup`:** executar **Modo 3** — invocar `meta-ads-pro/setup`.
- **`doctor`:** executar **Modo 4** — invocar `meta-ads-pro/doctor`.
- **Intenção em linguagem natural** (ex: "sobe campanha de WhatsApp com lead form", "lista campanhas ativas", "importa conta existente"): executar **Modo 5** — invocar `meta-ads-pro/orquestradora` com o argumento literal como intenção do usuário.
- **Qualquer outra string curta não reconhecida:** executar **Modo 6** — fallback com menu principal.

**Match case-insensitive** nos modos 2/3/4. Nos modos 5/6, use bom senso: se tem mais de 3 palavras ou parece pedido/intenção, é Modo 5.

---

## Modo 1 — Menu principal (sem args)

**Imprima o banner ASCII abaixo direto no output (sem tool use, sem Bash, sem Read)** — é apenas texto pra você reproduzir byte-exato:

```
 ███╗   ███╗ ███████╗ ████████╗  █████╗       █████╗  ██████╗  ███████╗
 ████╗ ████║ ██╔════╝ ╚══██╔══╝ ██╔══██╗     ██╔══██╗ ██╔══██╗ ██╔════╝
 ██╔████╔██║ █████╗      ██║    ███████║     ███████║ ██║  ██║ ███████╗
 ██║╚██╔╝██║ ██╔══╝      ██║    ██╔══██║     ██╔══██║ ██║  ██║ ╚════██║
 ██║ ╚═╝ ██║ ███████╗    ██║    ██║  ██║     ██║  ██║ ██████╔╝ ███████║
 ╚═╝     ╚═╝ ╚══════╝    ╚═╝    ╚═╝  ╚═╝     ╚═╝  ╚═╝ ╚═════╝  ╚══════╝
                                                                     PRO
───────────────────────────────────────────────────────────────────────

 _            ____   __ _          _           _
| |__ _  _   / __ \ / _| |__ ___ _(_)___  __ _| |_  ___ _  _
| '_ \ || | / / _` |  _| / _` \ V / / _ \/ _` | ' \/ _ \ || |
|_.__/\_, | \ \__,_|_| |_\__,_|\_/|_\___/\__,_|_||_\___/\_, |
      |__/   \____/                                     |__/
```

Em seguida, imprima o menu principal BYTE-EXATO abaixo:

```
╔══════════════════════════════════════════════════════════════════╗
║  🎯 Comandos disponíveis (v1.0.2)                                ║
╠══════════════════════════════════════════════════════════════════╣
║                                                                  ║
║  ⚙  SETUP & SAÚDE                                                ║
║     /meta-ads-setup ........ Config inicial do projeto (.env)    ║
║     /meta-ads-doctor ....... Pre-flight (10 checks + --fix)      ║
║                                                                  ║
║  🚀 CRIAR                                                        ║
║     /meta-ads-campanha ..... Nova campanha (5 objetivos)         ║
║     /meta-ads-conjuntos .... Ad sets (targeting, budget, date)   ║
║     /meta-ads-anuncios ..... Anúncios (normal ou dinâmico)       ║
║     /meta-ads-lead-forms ... Lead form (qualifier/disqualifier)  ║
║                                                                  ║
║  📊 GERENCIAR                                                    ║
║     /meta-ads-publicos ..... Públicos customizados/lookalike     ║
║     /meta-ads-regras ....... Regras automatizadas                ║
║     /meta-ads-insights ..... Métricas + reports                  ║
║                                                                  ║
║  🔄 IMPORT & ROLLBACK                                            ║
║     /meta-ads-import-existing ... GET-only da conta Meta         ║
║     /meta-ads-rollback {run_id} . Desfaz uma run (topológico)    ║
║                                                                  ║
║  🛠  META                                                         ║
║     /meta-ads-update ............. Puxa nova versão do plugin    ║
║     /meta-ads-analyze-telemetry .. Relatório local de uso        ║
║                                                                  ║
╚══════════════════════════════════════════════════════════════════╝

💡 Primeira vez aqui? Digite:  /meta-ads jornadas
💡 Quer ir direto? Descreve: /meta-ads sobe campanha de WhatsApp
```

---

## Modo 2 — Jornadas (`$ARGUMENTS` == "jornadas")

Imprimir as 4 boxes BYTE-EXATO abaixo:

```
╔══════════════════════════════════════════════════════════════════╗
║  1️⃣   PRIMEIRA VEZ NO PROJETO                                     ║
╠══════════════════════════════════════════════════════════════════╣
║                                                                  ║
║  /meta-ads-setup                                                 ║
║     └─ valida token, descobre contas/pages/pixels,               ║
║        salva .env + CLAUDE.md                                    ║
║                                                                  ║
║  /meta-ads-doctor                                                ║
║     └─ 10 checks (token, scopes, app mode, rate limit,           ║
║        ad account, page token, pixel, CLAUDE.md, learnings)     ║
║                                                                  ║
║  /meta-ads                                                       ║
║     └─ descreve o que quer fazer em linguagem natural            ║
║                                                                  ║
╚══════════════════════════════════════════════════════════════════╝

╔══════════════════════════════════════════════════════════════════╗
║  2️⃣   SUBIR CAMPANHA COMPLETA (end-to-end)                        ║
╠══════════════════════════════════════════════════════════════════╣
║                                                                  ║
║  /meta-ads sobe campanha de <destino> com R$ X/dia               ║
║     └─ orquestradora roteia:                                     ║
║        campanha → conjuntos → (lead-form?) → anúncios            ║
║                                                                  ║
║  Destinos suportados:                                            ║
║   • site externo (WEBSITE)                                       ║
║   • lead form (ON_AD)                                            ║
║   • WhatsApp (WHATSAPP)                                          ║
║   • Messenger (MESSENGER)                                        ║
║   • chamada (PHONE_CALL)                                         ║
║                                                                  ║
║  Rollback transacional automático em caso de falha mid-run.      ║
║                                                                  ║
╚══════════════════════════════════════════════════════════════════╝

╔══════════════════════════════════════════════════════════════════╗
║  3️⃣   IMPORTAR CONTA EXISTENTE (GET-only, zero escrita)           ║
╠══════════════════════════════════════════════════════════════════╣
║                                                                  ║
║  /meta-ads-import-existing                                       ║
║     └─ paginação cursor-based de campanhas/adsets/ads            ║
║     └─ snapshot timestamped em history/                          ║
║     └─ token redacted no output                                  ║
║                                                                  ║
║  /meta-ads analisa o import e diz o que tá pegando bem           ║
║     └─ orquestradora cruza com /meta-ads-insights                ║
║                                                                  ║
╚══════════════════════════════════════════════════════════════════╝

╔══════════════════════════════════════════════════════════════════╗
║  4️⃣   ALGO DEU RUIM (debug + rollback)                            ║
╠══════════════════════════════════════════════════════════════════╣
║                                                                  ║
║  /meta-ads-doctor --fix                                          ║
║     └─ tenta auto-recuperar (token refresh, page token, etc)     ║
║                                                                  ║
║  /meta-ads-rollback {run_id}                                     ║
║     └─ desfaz objetos criados em uma run específica              ║
║     └─ ordem topológica: ad → creative → image → adset →         ║
║        campaign → leadgen_form                                   ║
║     └─ idempotente em 404, retry em 613/80004                    ║
║                                                                  ║
║  /meta-ads-analyze-telemetry                                     ║
║     └─ top erros, taxa de sucesso, duração média                 ║
║                                                                  ║
╚══════════════════════════════════════════════════════════════════╝

💡 Próximo passo? Digite:  /meta-ads setup   (começa do zero)
💡 Ou descreve direto:    /meta-ads <sua intenção>
```

---

## Modo 3 — Setup (`$ARGUMENTS` == "setup")

Invoque a skill `meta-ads-pro/setup` seguindo o fluxo de 11 passos documentado em `skills/setup/SKILL.md`. Use as libs: `lib/graph_api.sh`, `lib/nomenclatura.sh`, `lib/telemetry.sh`.

---

## Modo 4 — Doctor (`$ARGUMENTS` == "doctor")

Invoque a skill `meta-ads-pro/doctor` com os 10 checks de preflight documentados em `skills/doctor/SKILL.md`. Use `lib/preflight.sh`.

---

## Modo 5 — Intenção em linguagem natural

O usuário descreveu uma intenção (ex: "sobe campanha de WhatsApp com lead form", "lista campanhas ativas", "pausa anúncio X", "importa conta existente e mostra top 5 ads").

Invoque a skill `meta-ads-pro/orquestradora` seguindo o fluxo documentado em `skills/orquestradora/SKILL.md`. Passe `$ARGUMENTS` como intenção do usuário.

A orquestradora vai:
1. Renderizar banner na primeira vez no projeto
2. Disparar `/meta-ads-doctor --silent` (preflight)
3. Rotear pra sub-skill correta baseado na intenção
4. Executar com rollback transacional + telemetria

---

## Modo 6 — Fallback (string curta não reconhecida)

Se `$ARGUMENTS` for uma string curta que não bate com `jornadas`, `setup`, `doctor`, nem parece intenção completa, imprima:

```
Não reconheci "$ARGUMENTS" como comando ou intenção.

Tenta:
  /meta-ads              → menu principal
  /meta-ads jornadas     → fluxos típicos
  /meta-ads setup        → config inicial
  /meta-ads doctor       → pre-flight
  /meta-ads <intenção>   → descreve em linguagem natural
                           (ex: "sobe campanha de WhatsApp R$ 50/dia")
```

Depois imprima o menu principal do Modo 1.
