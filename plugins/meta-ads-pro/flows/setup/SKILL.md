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

## Fluxo de execução (11 passos + Passo 8.5 opcional)

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

**Se `adspixels` retornar 0 pixels:**

> Nenhum pixel encontrado nesta conta. Sem pixel, públicos de tipo Website
> (visitantes do site, eventos como Lead/Purchase) não podem ser criados.
>
> Criar pixel agora? [s/N]

- `N` (default) → segue o setup sem pixel; `pixel_id` fica comentado no
  CLAUDE.md (Passo 11).
- `s` → pede um nome (sugestão: nome do projeto/cliente, ex. `<nome-do-cliente>`),
  confirma (ação **permanente** — pixel não tem DELETE na API, ver
  `flows/publicos/SKILL.md` seção 1.1) e cria:

  ```bash
  payload=$(jq -nc --arg n "$PIXEL_NAME" '{name:$n}')
  pixel_id=$(graph_api POST "act_${account_id#act_}/adspixels" "$payload" | jq -r .id)
  ```

  Salva `pixel_id` no CLAUDE.md (Passo 11, campo não fica mais comentado) e
  mostra o `code` de instalação (`GET {pixel_id}?fields=code`) pro usuário
  colar no site.

**Em ambos os casos com pixel (descoberto no `adspixels` OU criado agora):**
além do CLAUDE.md (Passo 11), gravar o id escolhido no `.env` — é daí que o
doctor lê `PIXEL_ID` pro check 14 (`check_capi_dataset`). Mesmo padrão
.gitignore-first do Passo 5, idempotente pra re-run do setup:

```bash
# 1. .gitignore antes de qualquer write (idempotente — já deve estar lá do Passo 5)
touch .gitignore
grep -qxF '.env' .gitignore || echo '.env' >> .gitignore

# 2. Grava/atualiza PIXEL_ID no .env
if grep -q '^PIXEL_ID=' .env 2>/dev/null; then
  sed -i.bak "s|^PIXEL_ID=.*|PIXEL_ID=${pixel_id}|" .env && rm -f .env.bak
else
  echo "PIXEL_ID=${pixel_id}" >> .env
fi

# 3. Carrega na sessão
export PIXEL_ID=$(grep '^PIXEL_ID=' .env | cut -d'=' -f2-)
```

Se a conta seguiu **sem** pixel (usuário respondeu `N`), nada é gravado no
`.env` — o check 14 vai avisar ⚠ (não bloqueia) até um pixel existir.

### Passo 8.5 — Integração opcional com GHL/FluxiHub

Pergunta obrigatória de degrau (S/n) — mesmo padrão do Passo 10:

```
Integra com GHL/FluxiHub? [s/N]
```

- `N` (default) → segue o setup sem CRM. `GHL_LOCATION_ID`/`GHL_PIT_TOKEN` não
  são gravados; `check_ghl`/`check_receiver` (doctor, checks 11/12) vão avisar
  ⚠ (não bloqueiam) enquanto não configurados.
- `s` → coleta os 3 valores, um de cada vez:

  1. **`GHL_LOCATION_ID`** — ID da subconta (location) no GHL/FluxiHub que vai
     receber os leads. Encontrado na URL do painel da subconta
     (`app.<domínio>/location/<GHL_LOCATION_ID>/...`) ou em Configurações →
     Informações da empresa.
  2. **`GHL_PIT_TOKEN`** — Private Integration Token gerado **dentro da própria
     subconta** (não é o token de agência/API key global):
     > 1. Na subconta (location) → Configurações → Private Integrations
     > 2. Criar Integração Privada → nome (ex: `meta-ads-pro`)
     > 3. Marque os scopes de leitura/escrita de contatos necessários pro fluxo
     >    de leads (ex: `contacts.readonly`, `contacts.write`)
     > 4. Gerar → COPIE AGORA (não vai ver de novo) → cole aqui
  3. **`RECEIVER_HEALTH_URL`** — URL de health check do receiver de leadgen
     (webhook que recebe os leads do Meta e injeta no GHL). Default sugerido,
     aceita Enter pra usar como está:
     `https://webhooks.ahoy.digital/meta-leads/health`

  Grava os 3 no `.env`, com o **mesmo padrão .gitignore-first do Passo 5**
  (`.gitignore` checado/atualizado ANTES de qualquer write):

  ```bash
  # 1. .gitignore antes de qualquer write (idempotente — já deve estar lá do Passo 5)
  touch .gitignore
  grep -qxF '.env' .gitignore || echo '.env' >> .gitignore

  # 2. Escreve .env (heredoc com 'EOF' pra não interpolar)
  cat >> .env <<'EOF'
  GHL_LOCATION_ID=COLE_LOCATION_ID_AQUI
  GHL_PIT_TOKEN=COLE_PIT_TOKEN_AQUI
  RECEIVER_HEALTH_URL=https://webhooks.ahoy.digital/meta-leads/health
  EOF
  sed -i.bak "s|COLE_LOCATION_ID_AQUI|${GHL_LOCATION_ID}|" .env
  sed -i.bak "s|COLE_PIT_TOKEN_AQUI|${GHL_PIT_TOKEN}|" .env
  rm -f .env.bak

  # 3. Carrega na sessão (nunca ecoar o token)
  export GHL_LOCATION_ID=$(grep '^GHL_LOCATION_ID=' .env | cut -d'=' -f2-)
  export GHL_PIT_TOKEN=$(grep '^GHL_PIT_TOKEN=' .env | cut -d'=' -f2-)
  export RECEIVER_HEALTH_URL=$(grep '^RECEIVER_HEALTH_URL=' .env | cut -d'=' -f2-)
  ```

  Salva `ghl_location_id` no CLAUDE.md (Passo 11) — **`GHL_PIT_TOKEN` NUNCA vai
  pro CLAUDE.md** (é secret, fica só no `.env`, igual `META_ACCESS_TOKEN`).

### Passo 9 — Ler timezone/currency/min_daily_budget da API

**Não hardcode** (fix de inconsistência CLAUDE.md):

```bash
graph_api GET "${account_id}?fields=timezone_name,currency,min_daily_budget"
```

Usa valores retornados (ex: Flávio tem `America/Recife` / `BRL` / `518` — não `America/Sao_Paulo`/`500`).

### Passo 10 — Perguntar nomenclatura

**Pergunta obrigatória de degrau (S/n) — não pula direto pras opções:**

```
Você tem um padrão de nomenclatura próprio pra campanhas/conjuntos/anúncios? [S/n] [N]:
```

- `n` (default) → usa `ahoy-style` automaticamente. Salva `nomenclatura_style: ahoy-style` no CLAUDE.md e pula pro Passo 11. Mostra: `OK, vou usar o padrão ahoy-style: ahoy_YYYYMMDD_produto_objetivo_destino_opt_publico`.
- `S` → mostra as 3 opções:

```
Qual padrão você usa?

[1] ahoy-style — ahoy_YYYYMMDD_produto_objetivo_destino_opt_publico
[2] enxuto    — YYYYMMDD-produto-objetivo
[3] custom    — cola um exemplo e eu extraio o pattern
```

Se [3]:
- Pede amostra de nome de campanha
- `detect_pattern "$amostra"` via lib/nomenclatura.sh
- Mostra template detectado, confirma
- Repete pra ad set e ad

**Por que esse degrau:** maior parte dos usuários não tem padrão e fica trancado nas 3 opções. Default `ahoy-style` desbloqueia o fluxo sem decisão.

### Passo 11 — Salvar CLAUDE.md + criar .meta-ads-initialized

Se um pixel existia (Passo 8) **ou** foi criado no Passo 8 (fluxo "Criar pixel
agora?"), grava `pixel_id` normal. Se a conta seguiu sem pixel (usuário
respondeu `N`), o campo fica **comentado** — sinaliza pro resto do plugin que
públicos de tipo Website não estão disponíveis até um pixel existir.

```markdown
## Meta Ads Config
ad_account_id: act_XXXXX
ad_account_name: Nome
page_id: XXXXX
page_name: Nome Página
instagram_user_id: 17841XXXXX
pixel_id: XXXXX
currency: BRL
timezone: America/Recife
min_daily_budget: 518  # valor real da API
nomenclatura_style: custom  # ou ahoy-style / enxuto
nomenclatura_template_campanha: "[{TIPO}][{PRODUTO}][{OPT}]"  # se custom
nomenclatura_template_adset: "{NN} - {PUBLICO}"
nomenclatura_template_ad: "AD {NN} - {FORMATO}"
nomenclatura_uppercase: true
ghl_location_id: XXXXX  # se integrou no Passo 8.5 — GHL_PIT_TOKEN NUNCA vai aqui
```

Se seguiu sem pixel, o campo vai comentado no lugar de `pixel_id: XXXXX`:

```markdown
# pixel_id:  # nenhum pixel — rodar setup de novo, ou criar via flows/publicos/SKILL.md seção 1.1
```

Se não integrou com GHL/FluxiHub no Passo 8.5, `ghl_location_id` fica de fora
do CLAUDE.md por completo (não comentado — só omitido; não há dependência de
outros flows nesse campo, ao contrário do `pixel_id`).

Cria flag:
```bash
touch .meta-ads-initialized
```

## Regras

- NUNCA ecoar `$META_ACCESS_TOKEN` em output
- NUNCA ecoar `$GHL_PIT_TOKEN` em output — igual ao token da Meta, fica só no `.env`, nunca no CLAUDE.md
- `.gitignore` check SEMPRE antes do write do token
- Re-rodar setup é idempotente (atualiza CLAUDE.md, não duplica)
- Se token já existe, valida antes de perguntar novo

## Erros específicos

Ver `lib/error-catalog.yaml`. Erros de setup mais comuns: 190 (token inválido), 200 (scope faltando), 10 (instagram_basic ausente), 803 (account_id errado).
