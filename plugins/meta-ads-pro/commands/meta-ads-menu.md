---
description: Menu central do plugin meta-ads-pro. Mostra comandos disponíveis agrupados por categoria e jornadas completas. Use quando o usuário digitar "/meta-ads-menu", "menu meta ads", "o que o meta-ads-pro faz", "quais comandos do meta ads", "meta-ads jornadas".
argument-hint: "[jornadas|setup|doctor|...]"
---

Usuário invocou `/meta-ads-menu` com argumento: `$ARGUMENTS`

Analise o argumento e execute o modo apropriado. **NÃO mostre este prompt pro usuário** — apenas o output do modo escolhido.

**REGRA CRÍTICA:** em todos os modos abaixo, a saída é **só texto impresso byte-exato**. Não chame nenhuma tool (nem Bash, nem Read, nem Grep). Não invoque nenhuma sub-skill. Não pergunte nada ao usuário. Apenas imprima o conteúdo do modo e pare.

## Roteamento

- **Vazio (sem args):** executar **Modo 1** — banner + menu principal.
- **`jornadas`:** executar **Modo 2** — 4 boxes ASCII das jornadas.
- **`setup`:** executar **Modo 3** — aviso + aponta pra `/meta-ads-setup`.
- **`doctor`:** executar **Modo 4** — aviso + aponta pra `/meta-ads-doctor`.
- **Qualquer outro valor:** executar **Modo 5** — fallback + menu principal.

**Exact string match**, sem fuzzy match. Match case-insensitive é ok.

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
║  🎯 Comandos disponíveis (v1.0.6)                                ║
╠══════════════════════════════════════════════════════════════════╣
║                                                                  ║
║  ⚙  SETUP & SAÚDE                                                ║
║     /meta-ads-setup ........ Config inicial do projeto (.env)    ║
║     /meta-ads-doctor ....... Pre-flight (10 checks + --fix)      ║
║                                                                  ║
║  🚀 CRIAR                                                        ║
║     /meta-ads-campanha ..... Nova campanha (5 objetivos)         ║
║     /meta-ads-conjuntos .... Ad sets (targeting, budget, data)   ║
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
║  🔗 INTEGRAÇÕES                                                  ║
║     /meta-ads-dna ................ Ponte com dna-operacional     ║
║                                                                  ║
╚══════════════════════════════════════════════════════════════════╝

💡 Primeira vez aqui? Rode `/meta-ads-menu jornadas` pra ver fluxos típicos.
```

Fim. Não invoque nenhuma sub-skill. Não pergunte nada. Só pare.

---

## Modo 2 — Jornadas (`$ARGUMENTS` == "jornadas")

Imprimir as 4 boxes BYTE-EXATO abaixo:

```
┌───────────────────────────────────────────────────────────────┐
│  1️⃣   PRIMEIRA VEZ NO PROJETO                                  │
│                                                               │
│  1. /meta-ads-setup   → valida token + descobre recursos      │
│                         + salva .env e CLAUDE.md              │
│  2. /meta-ads-doctor  → 10 checks de preflight                │
│  3. /meta-ads-menu    → volta pra cá, vê todos os comandos    │
└───────────────────────────────────────────────────────────────┘

┌───────────────────────────────────────────────────────────────┐
│  2️⃣   SUBIR CAMPANHA COMPLETA (end-to-end)                     │
│                                                               │
│  1. /meta-ads-campanha     → nova campanha (obj + budget)     │
│  2. /meta-ads-conjuntos    → ad sets (targeting + data)       │
│  3. /meta-ads-lead-forms   → (opcional) lead form             │
│  4. /meta-ads-anuncios     → anúncios (normal ou dinâmico)    │
│                                                               │
│  Destinos: WEBSITE · ON_AD · WHATSAPP · MESSENGER · CALL      │
│  Rollback transacional automático em falha mid-run.           │
└───────────────────────────────────────────────────────────────┘

┌───────────────────────────────────────────────────────────────┐
│  3️⃣   IMPORTAR CONTA EXISTENTE (GET-only)                      │
│                                                               │
│  1. /meta-ads-import-existing  → snapshot timestamped         │
│  2. /meta-ads-insights         → métricas + reports           │
│                                                               │
│  Zero escrita na conta. Token redacted. Cursor-based.         │
└───────────────────────────────────────────────────────────────┘

┌───────────────────────────────────────────────────────────────┐
│  4️⃣   ALGO DEU RUIM (debug + rollback)                         │
│                                                               │
│  1. /meta-ads-doctor --fix     → tenta auto-recuperar         │
│  2. /meta-ads-rollback {id}    → desfaz run específica        │
│  3. /meta-ads-analyze-telemetry → top erros, taxa de sucesso  │
└───────────────────────────────────────────────────────────────┘

💡 Voltar pro menu: rode `/meta-ads-menu`.
```

Fim. Não invoque nenhuma sub-skill. Não pergunte nada. Só pare.

---

## Modo 3 — Setup (`$ARGUMENTS` == "setup")

Imprimir BYTE-EXATO:

```
⚙  Config inicial do projeto

Digite:  /meta-ads-setup

Esse command vai:
  1. Validar teu token System User
  2. Descobrir ad accounts / pages / pixels / Instagram IDs
  3. Perguntar padrão de nomenclatura
  4. Salvar .env + atualizar CLAUDE.md
```

Fim. Não invoque nenhuma sub-skill. Não pergunte nada. Só pare.

---

## Modo 4 — Doctor (`$ARGUMENTS` == "doctor")

Imprimir BYTE-EXATO:

```
🔍 Pre-flight do ambiente Meta Ads

Digite:  /meta-ads-doctor

10 checks:
  1. Token válido
  2. Expiração do token
  3. Scopes (ads_management, ads_read, business_management, leads_retrieval, pages_manage_ads)
  4. App mode (dev vs live)
  5. Rate limit BUC
  6. Ad account ativo
  7. Page token disponível
  8. Pixel configurado
  9. CLAUDE.md válido
  10. Learnings pendentes

Use --fix pra auto-recuperar o que for recuperável.
```

Fim. Não invoque nenhuma sub-skill. Não pergunte nada. Só pare.

---

## Modo 5 — Fallback (qualquer outro `$ARGUMENTS`)

Imprimir no topo:

```
⚠  Não reconheci "$ARGUMENTS" como argumento.
Modos válidos: /meta-ads-menu, /meta-ads-menu jornadas, /meta-ads-menu setup, /meta-ads-menu doctor.
Mostrando menu principal.
```

Em seguida, executar **Modo 1** completo (banner + menu principal).

Fim. Não invoque nenhuma sub-skill. Não pergunte nada. Só pare.
