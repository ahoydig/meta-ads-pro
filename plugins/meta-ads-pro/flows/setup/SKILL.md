---
name: meta-ads-setup
description: Configuração inicial do Meta Ads no projeto — valida token System User, descobre contas/pages/pixels/Instagram, pergunta padrão de nomenclatura customizada, salva tudo em .env + CLAUDE.md. Fix dos bugs #6 e #10 do caso Filipe.
---

# meta-ads-setup

Configuração inicial do sistema Meta Ads. Executa uma vez por projeto.

## Pré-requisitos

1. Token **System User** gerado no Business Manager da Meta (não token pessoal)
2. App Meta com acesso à Marketing API
3. Scopes obrigatórios: `ads_management`, `ads_read`, `business_management`, `instagram_basic`, `leads_retrieval`, `pages_manage_ads`

## Fluxo de execução (11 passos)

### Passo 1 — Check .env

```bash
grep -q '^META_ACCESS_TOKEN=' .env 2>/dev/null && echo "FOUND" || echo "NOT_FOUND"
```

Se `FOUND`:
- Lê token: `TOKEN=$(grep '^META_ACCESS_TOKEN=' .env | cut -d'=' -f2-)`
- Pula pro Passo 5 (validação)

Se `NOT_FOUND`:
- Pergunta ao usuário: "Já tem token System User? [S]im / [N]ão / [?] não sei"
- Se S → pede pra colar token, salva e pula pro Passo 5
- Se N/? → guia ETAPAS A-D (próximos passos)

### Passo 2 — ETAPA A: Criar app no Meta Developers

Apresenta UMA POR VEZ (nunca tudo de uma vez):

> **Criando o App:**
> 1. Acesse https://developers.facebook.com/apps/create/
> 2. "O que deseja criar?" → Outro
> 3. "Tipo" → Negócios (Business)
> 4. Nome: `Claude Code Ads` · Email: seu · Conta: Business Manager
> 5. Criar Aplicativo
> 6. Painel → Adicionar Produto → **API de Marketing** → Configurar
>
> Avise quando terminar.

**Para e aguarda confirmação antes do Passo 3.**

### Passo 3 — ETAPA B: Criar System User no Business Manager

> **Usuário do Sistema:**
> 1. https://business.facebook.com/settings/system-users
> 2. Adicionar (botão azul)
> 3. Nome: `Claude Code` · Cargo: Administrador
> 4. Criar Usuário do Sistema
> 5. **Não feche a página** — vamos precisar

### Passo 4 — ETAPA C+D: Vincular conta + Gerar token

> **Vincular Conta:**
> 1. Clique no usuário criado → Adicionar Ativos → Contas de Anúncios
> 2. Selecione conta + Ative "Controle Total" → Salvar
>
> **Gerar Token:**
> 1. Com o usuário selecionado → Gerar Novo Token
> 2. Selecione o app da ETAPA A
> 3. **Marque 5 scopes:** `ads_management`, `ads_read`, `business_management`, `instagram_basic`, `leads_retrieval`
> 4. Expiração: **Nunca** (selecione "Never")
> 5. Gerar Token → COPIE AGORA (não vai ver de novo)
> 6. Cole aqui

**Validação básica do que o usuário colou:**
- Começa com `EAA`?
- Tem ≥ 100 caracteres?
- Se não passar: "Esse token parece incompleto. Tokens começam com EAA e têm ~200 chars. Colou tudo?"

### Passo 5 — Salvar em .env (.gitignore FIRST)

**ORDEM CRÍTICA** (fix bug install.sh atual):

```bash
# 1. .gitignore antes de qualquer write do token
touch .gitignore
grep -qxF '.env' .gitignore || echo '.env' >> .gitignore

# 2. Agora escreve .env (heredoc correto com 'EOF' pra não interpolar)
cat >> .env <<'EOF'
META_ACCESS_TOKEN=COLE_TOKEN_AQUI
META_API_VERSION=v25.0
EOF
# Substitui COLE_TOKEN_AQUI pelo token real via sed
sed -i.bak "s|COLE_TOKEN_AQUI|${TOKEN}|" .env && rm -f .env.bak

# 3. Carrega na sessão (anchor + -f2- cobre token com = dentro)
export META_ACCESS_TOKEN=$(grep '^META_ACCESS_TOKEN=' .env | cut -d'=' -f2-)
```

### Passo 6 — Validar token

```bash
graph_api GET "me?fields=name,id"
```

Expected: `{"name":"...","id":"..."}`
Se erro 190 → token inválido, retorna ao Passo 1.

### Passo 7 — Listar contas de anúncio

```bash
graph_api GET "me/adaccounts?fields=name,account_status,currency,amount_spent,timezone_name"
```

Se 1 conta → auto-seleciona.
Se múltiplas → mostra tabela, pergunta qual usar.
Se 0 → erro, orienta vincular conta no Business Manager.

### Passo 8 — Descobrir pages, pixels, Instagram

Roda em paralelo:

```bash
# Pages
graph_api GET "${account_id}/promote_pages?fields=name,id,fan_count"

# Pixels
graph_api GET "${account_id}/adspixels?fields=name,id,last_fired_time"

# Instagram (cascata 4 tentativas — igual skill atual)
graph_api GET "${account_id}/connected_instagram_accounts?fields=username,id,followers_count"
# se vazio → business_id via account
# se vazio → me/accounts com connected_instagram_account
# se vazio → owned_instagram_accounts do business
# se vazio → pergunta ao user cole manual
```

Se múltiplos resultados por categoria → pergunta qual é principal.

### Passo 9 — Ler timezone/currency/min_daily_budget da API

**Não hardcode** (fix de inconsistência CLAUDE.md):

```bash
graph_api GET "${account_id}?fields=timezone_name,currency,min_daily_budget"
```

Usa valores retornados (ex: Flávio tem `America/Recife` / `BRL` / `518` — não `America/Sao_Paulo`/`500`).

### Passo 10 — Perguntar nomenclatura

```
Qual padrão de nomenclatura você usa?

[1] ahoy-style — ahoy_YYYYMMDD_produto_objetivo_destino_opt_publico
[2] enxuto — YYYYMMDD-produto-objetivo
[3] custom — cola um exemplo e eu extraio o pattern
```

Se [3]:
- Pede amostra de nome de campanha
- `detect_pattern "$amostra"` via lib/nomenclatura.sh
- Mostra template detectado, confirma
- Repete pra ad set e ad

### Passo 11 — Salvar CLAUDE.md + criar .meta-ads-initialized

```markdown
## Meta Ads Config
ad_account_id: act_XXXXX
ad_account_name: Nome
page_id: XXXXX
page_name: Nome Página
instagram_user_id: 17841XXXXX
pixel_id: XXXXX  # ou comentado se sem pixel
currency: BRL
timezone: America/Recife
min_daily_budget: 518  # valor real da API
nomenclatura_style: custom  # ou ahoy-style / enxuto
nomenclatura_template_campanha: "[{TIPO}][{PRODUTO}][{OPT}]"  # se custom
nomenclatura_template_adset: "{NN} - {PUBLICO}"
nomenclatura_template_ad: "AD {NN} - {FORMATO}"
nomenclatura_uppercase: true
```

Cria flag:
```bash
touch .meta-ads-initialized
```

## Regras

- NUNCA ecoar `$META_ACCESS_TOKEN` em output
- `.gitignore` check SEMPRE antes do write do token
- Re-rodar setup é idempotente (atualiza CLAUDE.md, não duplica)
- Se token já existe, valida antes de perguntar novo

## Erros específicos

Ver `lib/error-catalog.yaml`. Erros de setup mais comuns: 190 (token inválido), 200 (scope faltando), 10 (instagram_basic ausente), 803 (account_id errado).
