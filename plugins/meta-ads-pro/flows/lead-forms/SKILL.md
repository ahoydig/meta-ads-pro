---
name: meta-ads-lead-forms
description: CRUD de Meta Instant Forms (lead forms nativos). Valida política de privacidade bilíngue PT+EN em 3 camadas, força thank you qualificado+desqualificado, suporta qualifier/disqualifier + conditional logic, export de leads pra CSV. Fix dos bugs #7 (privacy Instagram) e #8 (thank you dupla).
---

# meta-ads-lead-forms

CRUD completo de Instant Forms (formulários nativos da Meta que abrem dentro do Facebook/Instagram em vez de redirecionar pra site externo).

## Operações

- **Criar** — fluxo interativo de 9 passos (default)
- **Listar** — `/meta-ads-lead-forms list` → `GET /{page_id}/leadgen_forms`
- **Editar** — `/meta-ads-lead-forms edit {form_id}` → duplica + edita (Meta não permite editar form com leads coletados)
- **Deletar** — `/meta-ads-lead-forms delete {form_id}`
- **Export leads** — `/meta-ads-lead-forms export {form_id}` → `GET /{form_id}/leads` + CSV

## Fluxo de criação (9 passos)

### Passo 1 — Pre-flight

Doctor `--silent`. Valida:
- `META_ACCESS_TOKEN` setado
- `PAGE_ID` setado no `.env`/`CLAUDE.md`
- Token com scope `pages_manage_ads` + `leads_retrieval`
- Page token disponível (POST `/leadgen_forms` exige page token, não user token)

Se falhar: aborta com instrução clara de como resolver.

### Passo 2 — Nome interno (obrigatório)

Max 60 chars. Em testes automatizados, forçar prefixo `TEST_`.

```
Nome interno do form (só você vê, max 60 chars): ____
```

### Passo 3 — Intro screen (OBRIGATÓRIO — fix parcial bug #8)

```
Preencha a tela de INTRO (aparece ANTES das perguntas):

Título (max 60 chars): ____
Descrição (max 300 chars): ____
Imagem de intro (opcional, caminho local ou URL): ____
```

Validação: título + descrição não podem estar vazios.

Payload:
```json
{
  "context_card": {
    "title": "...",
    "content": ["..."],
    "image_url": "..."
  }
}
```

### Passo 4 — Perguntas pre-filled

Checkboxes com default selecionados:

```
Quais campos pré-preencher do perfil Meta do usuário?

[x] Nome completo (FULL_NAME) — default
[x] E-mail (EMAIL) — default
[x] Telefone (PHONE) — default
[ ] Cidade (CITY)
[ ] Estado (STATE)
[ ] CEP (ZIP)
[ ] Data de nascimento (DOB)
[ ] Gênero (GENDER)
```

Payload:
```json
{
  "questions": [
    {"type": "FULL_NAME"},
    {"type": "EMAIL"},
    {"type": "PHONE"}
  ]
}
```

### Passo 5 — Perguntas customizadas (até 15)

Pra cada pergunta:

```
Tipo:
[s] short_answer — resposta livre
[m] multiple_choice — opções (2-10)
[c] conditional — mostra só se outra pergunta = X

Label (max 200 chars): ____

Se multiple_choice:
  Opção 1: ____
  Opção 2: ____
  ...

Qualifier?
[q] Qualifica (resposta X = lead bom)
[d] Desqualifica (resposta X = lead ruim)
[n] Neutra (sem filtro)
```

Conditional logic (se tipo=c):
```
Mostre essa pergunta SE:
Pergunta ____ (label ou key) = ____
```

**Segurança:** labels e option values vêm do usuário. Passar sempre via `jq --arg` ou stdin pro Python — nunca via heredoc (FU-1).

Payload exemplo:
```json
{
  "questions": [
    {"type": "FULL_NAME"},
    {
      "type": "CUSTOM",
      "key": "procedure_interest",
      "label": "Qual procedimento?",
      "input_type": "MULTIPLE_CHOICE",
      "options": [
        {"value": "Extração", "key": "ext"},
        {"value": "Gengivoplastia", "key": "geng"}
      ]
    }
  ]
}
```

### Passo 6 — Privacy policy URL (3 camadas bilíngue — FIX BUG #7)

```
URL da política de privacidade: ____
```

Valida via `lib/privacy-validator.sh::validate_privacy_url`:

- **Camada 1 — Blacklist:**
  - `instagram.com/*` (+ subdomains) → rejeita (caso Filipe)
  - `facebook.com/*/posts` → rejeita
  - `linktr.ee/*` → rejeita
  - `beacons.ai/*` → rejeita

- **Camada 2 — Estrutural:**
  - HEAD 200 obrigatório
  - Fallback GET se servidor retornar 405 Method Not Allowed
  - Se ambos falharem → rejeita

- **Camada 3 — Conteúdo bilíngue:**
  - Texto ≥ 300 chars (sem tags)
  - Pelo menos 1 heading (`<h1>`, `<h2>` ou `<title>`) com "privacid" ou "privacy"
  - Pelo menos 1 keyword PT (`privacidade`, `política de privacidade`, `dados pessoais`, `LGPD`, `lei 13.709`)
    OU EN (`privacy policy`, `personal data`, `GDPR`, `data protection`, `CCPA`)

Se rejeita, oferece:
1. Template LGPD pronto (link pro doc interno)
2. Opções de hospedagem rápida: Notion público, Google Docs público, Facebook Note, WordPress.com

Cache de 24h em `~/.claude/meta-ads-pro/cache/privacy/{sha256(url)}`. Invalidar via `invalidate_privacy_cache "$url"` se o user corrigir a página.

**IMPORTANTE:** validação SEMPRE antes do POST. Skill recusa criação se Camada 1/2/3 reprovar.

### Passo 7 — Thank you screen QUALIFICADO (OBRIGATÓRIO)

Usuário que PASSOU no filtro (qualificado) vai ver:

```
Título: ____
Descrição: ____
CTA button:
  [1] Ligar agora (CALL) — requer telefone
  [2] Visitar site (VIEW_URL) — requer URL
  [3] Baixar arquivo (DOWNLOAD) — requer URL de PDF
  [4] WhatsApp (MESSAGE) — requer número
```

Payload:
```json
{
  "thank_you_page": {
    "title": "Recebemos!",
    "body": "Nossa equipe entra em contato.",
    "button_type": "CALL",
    "button_text": "Ligar agora",
    "country_code": "BR",
    "phone_number": "55..."
  }
}
```

### Passo 8 — Thank you screen DESQUALIFICADO (OBRIGATÓRIO — FIX BUG #8)

Campo crítico que a skill atual pulava. Forçar preenchimento:

```
Usuário que NÃO passou no filtro (desqualificado) vai ver:

Título: ____ (ex: "Obrigado pelo interesse!")
Descrição: ____ (ex: "Nesse momento não temos vagas pro seu perfil. Siga no IG.")
CTA distinto do qualificado:
  [1] Visitar Instagram / outra rede
  [2] Sem CTA (só a mensagem)
```

Payload:
```json
{
  "disqualified_thank_you_page": {
    "title": "Obrigado!",
    "body": "Siga nosso Instagram",
    "button_type": "VIEW_URL",
    "button_text": "Ir pro Instagram",
    "website_url": "https://instagram.com/foo"
  }
}
```

**Se user tentar pular este passo, skill recusa criação com:**
> "Lead forms precisam de thank you QUALIFICADO E DESQUALIFICADO desde v1.0.0. Fix do caso Filipe (bug #8). Preencha o passo 8 ou cancele."

Client-side check (pré-POST):
```bash
# forma canônica: jq -e pra ambos campos
echo "$payload" | jq -e '.thank_you_page and .disqualified_thank_you_page' >/dev/null \
  || { echo "✗ thank you dupla obrigatória"; exit 1; }
```

### Passo 9 — POST + manifest

```bash
# graph_api.sh já aplica retry + error-resolver + DRY_RUN
graph_api POST "${PAGE_ID}/leadgen_forms" "$payload"
```

Payload final (montado via `jq -n`, nunca via heredoc):
```json
{
  "name": "TEST_...",
  "questions": [...],
  "context_card": {...},
  "thank_you_page": {...},
  "disqualified_thank_you_page": {...},
  "privacy_policy": {"url": "https://..."},
  "follow_up_action_url": "https://..."
}
```

Retorna `form_id`. Registra no manifest:
```bash
python3 lib/_py/manifest.py add leadgen_form "$form_id" --meta "{\"name\":\"...\"}"
```

## Operações auxiliares

### `--list` — listar forms existentes

```bash
graph_api GET "${PAGE_ID}/leadgen_forms?fields=id,name,status,leads_count,created_time&limit=100"
```

Mostra tabela: `ID | Nome | Status | Leads coletados | Criado em`.

### `--edit {form_id}` — duplicar + editar

Meta não permite editar form com leads. Fluxo:
1. `GET /{form_id}?fields=name,questions,context_card,thank_you_page,disqualified_thank_you_page,privacy_policy,follow_up_action_url`
2. Mostra diff do que pode mudar
3. Cria form novo via duplicate (POST com payload modificado)
4. Opcional: deleta o antigo se `status = DRAFT`

### `--export {form_id}` — leads pra CSV

```bash
graph_api GET "${form_id}/leads?fields=id,created_time,field_data&limit=500"
```

Converte pra CSV via `python3 lib/_py/leads_to_csv.py` (a ser criado em CP3c).

### `--delete {form_id}`

```bash
graph_api DELETE "${form_id}"
```

Remove do manifest.

## Regras invioláveis

1. **8 campos obrigatórios**, nenhum pode estar vazio:
   - `name`
   - `questions` (≥1 pre-filled)
   - `context_card`
   - `privacy_policy.url` (validada 3 camadas)
   - `thank_you_page`
   - `disqualified_thank_you_page`
2. **Privacy URL Instagram → rejeita** (blacklist — bug #7).
3. **Cache de validação privacy: 24h** via sha256 do URL.
4. **Thank you desqualificado SEMPRE obrigatório** (fix bug #8). Recusa client-side antes do POST.
5. **Page token** obrigatório pra POST (não user token).
6. **Zero echo/printf com `$META_ACCESS_TOKEN`** — usar sempre via `graph_api`.
7. **Labels/options user-controlled passam via `jq --arg` ou stdin**, nunca heredoc (FU-1).

## Erros específicos

Ver `lib/error-catalog.yaml`:
- `2657` — `form_id` inválido
- `100` sub `1487194` — privacy policy URL inválida (Meta-side double-check)
- `190` — token expirado/revogado
- `200` — scope faltando (`leads_retrieval` ou `pages_manage_ads`)
- `2656` — não pode deletar form com lookalikes dependentes

## Ganchos com outras skills

- **`flows/anuncios/`** — quando `destination_type=LEAD_FORM`, orquestradora aciona `/meta-ads-lead-forms` antes pra obter `form_id`, depois injeta em `object_story_spec.link_data.lead_gen_form_id`.
- **`lib/graph_api.sh`** — todos os calls HTTP passam por ele (retry + error-resolver + DRY_RUN).
- **`lib/privacy-validator.sh`** — validação 3 camadas com cache 24h.
- **`lib/rollback.sh`** — `rollback leadgen_form {form_id}` reverte criação.
