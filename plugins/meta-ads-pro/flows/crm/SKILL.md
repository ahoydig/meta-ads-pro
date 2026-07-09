---
name: meta-ads-crm
description: Integração do pipeline de lead com GoHighLevel/FluxiHub — nativa GHL como transporte, webhook próprio (Task 9/10) como atribuição/backup, CAPI do funil via ação nativa do GHL. Valida conexão, guia o mapeamento de forms e testa ponta-a-ponta com test lead.
---

# meta-ads-crm

Pipeline de lead Meta → GoHighLevel (GHL/FluxiHub). Dois caminhos coexistem pro mesmo lead:

1. **Integração nativa do GHL com Facebook** (Settings → Integrations → Facebook) — o GHL
   puxa o lead direto da Meta e cria o contato na subconta. Transporte principal.
2. **Webhook próprio** (`webhook-receiver/`, Task 9/10) — recebe o evento `leadgen` da Meta,
   busca o lead completo e empurra pro GHL via `/contacts/upsert`. Serve de **atribuição
   detalhada** (UTMs mapeados explicitamente em `custom_fields`) e **backup** caso a nativa
   falhe ou não mapeie um campo.

Este flow **não substitui** nenhum dos dois — ele **valida** que ambos estão de pé
(`status`), **guia** o mapeamento da nativa na UI do GHL (`mapear`), e **testa**
ponta-a-ponta com um lead sintético (`testar`). CAPI do funil (`capi-setup`/`capi-testar`)
é a Task 12.

## Env necessárias (.env do projeto do cliente)

```bash
GHL_LOCATION_ID=...        # subconta do cliente no GHL
GHL_PIT_TOKEN=...          # Private Integration Token (Settings → Private Integrations
                           # da subconta, scopes contacts.readonly + contacts.write)
RECEIVER_HEALTH_URL=https://webhooks.ahoy.digital/meta-leads/health   # default
```

Essas 3 env são coletadas no **setup** (`flows/setup/SKILL.md`, Passo 8.5 — pergunta
opcional "Integra com GHL/FluxiHub? [s/N]"), gravadas no `.env` no mesmo padrão
gitignore-first do resto do plugin. **Não duplicar aqui** o fluxo de coleta — a spec
completa do Passo 8.5 está em
`docs/superpowers/plans/2026-07-09-upgrade-v1.1-operacao-ahoy.md` (Task 21, Step 2).
`[não verificado neste worktree]` — o Passo 8.5 ainda não existia em
`flows/setup/SKILL.md` no momento desta task (Track A); confirme que mesclou antes de
assumir que o setup já pergunta isso.

`GHL_PIT_TOKEN` **nunca** vai pro `CLAUDE.md` (só env/`.env`) — mesma regra do
`META_ACCESS_TOKEN`.

## Helper de chamada GHL (inline — o plugin não tem lib GHL própria)

```bash
ghl_api() {  # ghl_api GET|POST <path> [body]
  local method="$1" path="$2" body="${3:-}"
  local args=(-sS --max-time 15 -H "Authorization: Bearer ${GHL_PIT_TOKEN:?}" -H "Version: 2021-07-28")
  [[ "$method" == "POST" ]] && args+=(-X POST -H "Content-Type: application/json" -d "$body")
  curl "${args[@]}" "https://services.leadconnectorhq.com${path}"
}
```

**Guards:**
- `${GHL_PIT_TOKEN:?}` aborta com mensagem clara se a env não estiver setada — nunca deixa
  o `curl` rodar sem `Authorization` (o que devolveria 401 confuso).
- `Version: 2021-07-28` é a versão de API do GHL usada em todo o pipeline (mesma do
  `webhook-receiver/app.py::push_to_ghl` — manter em sincronia se um dia for atualizada).
- **Zero echo/printf com `$GHL_PIT_TOKEN`** — nem em log de debug, nem em `set -x`.

**Aviso de rótulo:** todo payload de resposta do GHL mostrado abaixo neste documento é
`[não verificado ao vivo — validar na T23]`. Não existe `GHL_PIT_TOKEN`/`GHL_LOCATION_ID`
reais ainda (a Private Integration da subconta de teste é pendência humana) — os formatos
de campo (`location.id`, `contacts[]`, `customFields[]`) seguem a convenção já usada e
testada em `webhook-receiver/app.py::push_to_ghl` (`POST /contacts/upsert`, já real neste
repo) e o exemplo do brief da Task 11; a documentação pública do GHL
(`highlevel.stoplight.io`) é uma SPA sem conteúdo estático — não foi possível confirmar o
schema exato por WebFetch nesta sessão. **Não tratar nenhum JSON abaixo como contrato
fechado** até a **Task 23** (validação live real do pipeline completo, quando a Private
Integration da subconta de teste existir) exercitar de verdade.

## Modo `status`

Pre-flight: doctor `--silent` primeiro (token Meta, ad account, scopes) — se o doctor já
bloqueia, nem chega a rodar os 3 checks abaixo.

3 checagens independentes, cada uma com fix embutido:

### Check 1 — GHL alcançável

```bash
[[ -z "${GHL_PIT_TOKEN:-}" || -z "${GHL_LOCATION_ID:-}" ]] && {
  echo "⚠ GHL não configurado (ok se não usa CRM) — rode /meta-ads-setup ou preencha .env manualmente"
} || {
  r=$(ghl_api GET "/locations/${GHL_LOCATION_ID}" 2>/dev/null)
  if echo "$r" | jq -e '.location.id' >/dev/null 2>&1; then
    echo "✓ GHL: subconta $(echo "$r" | jq -r .location.name)"
  else
    echo "✗ GHL token/location inválidos — regenere a Private Integration (Settings → Private Integrations)"
  fi
}
```

### Check 2 — Receiver up

```bash
url="${RECEIVER_HEALTH_URL:-https://webhooks.ahoy.digital/meta-leads/health}"
r=$(curl -sS --max-time 10 "$url" 2>/dev/null)
if echo "$r" | jq -e '.received_total' >/dev/null 2>&1; then
  echo "✓ Receiver up ($(echo "$r" | jq -r .received_total) leads recebidos, pushed=$(echo "$r" | jq -r .pushed), erros=$(echo "$r" | jq -r .errors))"
else
  echo "⚠ Receiver não respondeu JSON — leads seguem só pela nativa GHL (ver webhook-receiver/deploy/RUNBOOK.md)"
fi
```

`[fonte: verificado ao vivo nesta task]` — hoje (2026-07) o receiver está rodando **local**
na VPS (`127.0.0.1:8811`, confirmado no `RUNBOOK.md`), mas a rota pública em
`webhooks.ahoy.digital/meta-leads` ainda **não existe** no Cloudflare Tunnel (pendência
humana, `RUNBOOK.md` §8). `curl https://webhooks.ahoy.digital/meta-leads/health` responde
hoje **404** (é o catch-all do gateway Hermes em `:8644`, não o receiver) — o check acima
mostra corretamente o ⚠, não trava o comando.

### Check 3 — Página subscrita em leadgen

```bash
page_token=$(GRAPH_API_SKIP_RESOLVER=1 graph_api GET "${PAGE_ID}?fields=access_token" 2>/dev/null \
  | jq -r '.access_token // empty')
if [[ -z "$page_token" ]]; then
  echo "⚠ Não foi possível derivar page token — verifique check_page_token do doctor"
else
  r=$(curl -sS --max-time 10 \
    "https://graph.facebook.com/${META_API_VERSION:-v25.0}/${PAGE_ID}/subscribed_apps?fields=subscribed_fields&access_token=${page_token}" \
    2>/dev/null)
  if echo "$r" | jq -e '.data[]?.subscribed_fields | index("leadgen")' >/dev/null 2>&1; then
    echo "✓ Página subscrita em leadgen"
  else
    echo "✗ Página SEM subscrição leadgen — rode a subscrição do runbook (Task 10 / spike T4):
      curl -X POST \"https://graph.facebook.com/\${API_VERSION}/\${PAGE_ID}/subscribed_apps\" \\
        -d \"subscribed_fields=leadgen\" -d \"access_token=\${PAGE_TOKEN}\""
  fi
fi
```

**Achado importante (confirmado ao vivo nesta task, 2 chamadas contra a Meta):** o GET
`{PAGE_ID}/subscribed_apps` **não** aceitou o token de sistema/usuário (`META_ACCESS_TOKEN`)
nesta conta — precisou do **page token derivado** (`{PAGE_ID}?fields=access_token`),
mesmo padrão de `tests/08-lead-forms.sh::_cleanup_forms` e do spike
`docs/spikes/2026-07-webhook-leadgen.md`, seção 3. O rascunho de `check_leadgen_subscription`
no plano v1.1 (Task 21) usa `graph_api GET` direto, sem derivar page token — **atualizar
esse rascunho pra derivar page token** quando a Task 21 for implementada, senão o check
21-13 vai reportar falso-negativo. Página `108356564252733` confirmada subscrita em
`leadgen` nesta sessão (3ª+ confirmação — já tinha sido validado no spike T4 e no
`RUNBOOK.md` §9).

### Tabela de saída

```
/meta-ads-crm status

Meta-ads-crm — status da integração GHL

✓/⚠/✗ GHL alcançável       <fix se falhar>
✓/⚠   Receiver up           <fix se falhar>
✓/✗   Página subscrita      <fix se falhar>
```

**Doctor (Task 21) reusa estas 3 funções** (`check_ghl`, `check_receiver`,
`check_leadgen_subscription`) — quando a Task 21 mover isso pra `lib/preflight.sh`, copiar
os corpos acima como estão (já testados ao vivo aqui), com a correção do page token no
check 3.

## Modo `mapear {form_id}`

A integração nativa GHL↔Facebook é configurada **na UI do GHL**, não via API — não existe
endpoint pra "mapear campo X pro campo Y" programaticamente. Este modo é um **checklist
guiado**, não uma automação.

### Passo 1 — Buscar o form na Meta

```bash
graph_api GET "${form_id}?fields=name,questions,tracking_parameters"
```

Mostra nome e perguntas do form pro usuário confirmar que é o form certo antes de ir pro
GHL.

### Passo 2 — Checklist da UI do GHL

```
1. Abra a subconta → Settings → Integrations → Facebook
2. Confirme que a Página do form está conectada (mesma PAGE_ID do .env: <PAGE_ID>)
3. Form Fields Mapping → localize o form pelo nome: "<nome do Passo 1>"
   (se não aparecer: form criado DEPOIS da conexão — force um refresh da lista
    na própria tela, ou reconecte a integração)
4. Pra cada pergunta do form, mapeie pro campo de contato correspondente:
   - FULL_NAME  → Nome/Sobrenome
   - EMAIL      → E-mail
   - PHONE      → Telefone
   - CUSTOM     → mapear pro Custom Field do GHL (criar antes se não existir —
     Settings → Custom Fields → Add Field)
5. Salve o mapeamento.
```

### Passo 3 — Custom fields de atribuição (UTM)

O spike `docs/spikes/2026-07-leadform-avancado.md` (seção 1) provou que os
`tracking_parameters` do form propagam pro `field_data` do lead como campos próprios
(`utm_source`, `utm_campaign`, etc, lado a lado com `full_name`/`email`) — **não existe**
um bloco separado de UTM no payload. Confirmar que a UI do GHL mapeia esses mesmos campos
custom no Passo 2, ou (se a nativa não expuser tracking_parameters como campo mapeável)
contar só com o receiver pra atribuição.

Listar os custom fields já existentes na subconta e anotar os IDs:

```bash
ghl_api GET "/locations/${GHL_LOCATION_ID}/customFields"
```

`[não verificado ao vivo — validar na T23]` formato esperado da resposta (convenção GHL,
não exercitado):
```json
{"customFields": [{"id": "<CF_ID>", "name": "utm_source", "fieldKey": "contact.utm_source"}]}
```

Com os IDs em mãos, atualizar `webhook-receiver/config.json` (a partir de
`config.example.json`) na entrada da página do cliente:

```json
{
  "<PAGE_ID_DO_CLIENTE>": {
    "location_id": "<GHL_LOCATION_ID>",
    "ghl_token_env": "GHL_TOKEN_<CLIENTE>",
    "custom_fields": {
      "utm_campaign": "<CF_ID_UTM_CAMPAIGN>",
      "utm_source": "<CF_ID_UTM_SOURCE>",
      "utm_medium": "<CF_ID_UTM_MEDIUM>"
    }
  }
}
```

Isso alimenta o `push_to_ghl` do receiver (`webhook-receiver/app.py:41-52`) — a chave é o
nome do `tracking_parameter` no form, o valor é o ID do custom field no GHL. Sem essa
entrada preenchida, o receiver ainda empurra o contato (nome/email/phone), só não os UTMs
custom.

### Passo 4 — Lembrete de refresh

Form criado **depois** da conexão Facebook↔GHL pode não aparecer na lista de mapeamento
até a subconta forçar um refresh (reabrir a tela de integração, ou reconectar). Isso vale
pra todo `TEST_` form novo criado pelo modo `testar` abaixo.

## Modo `testar {form_id?}`

Testa o pipeline ponta-a-ponta com um **lead sintético** (`test_leads`, mecanismo validado
ao vivo em `docs/spikes/2026-07-leadform-avancado.md`, seção 2).

**Achado que muda o fluxo:** `test_leads` tem **limite de 1 por form** — a 2ª chamada no
mesmo form falha com `error_subcode 1892058` ("Test lead already exists for this form").
Por isso este modo **sempre cria um form `TEST_` novo por rodada** (não reusa `{form_id}`
passado como argumento pra disparar o test lead — se `{form_id}` for passado, é usado só
pra herdar nome-base/contexto do form real que está sendo validado; o test lead em si
sempre vai num form novo, efêmero, arquivado no final).

### Passo 1 — Criar o form `TEST_` (payload mínimo das Tasks 6-8)

```bash
form_name="TEST_crm_$(date +%Y%m%d_%H%M%S)"
PRIVACY_URL="${PRIVACY_URL:-https://lp.ahoy.digital/politicas-privacidade}"  # já validada 3 camadas (skill lead-forms)
source "$CLAUDE_PLUGIN_ROOT/lib/utm.sh"
tp=$(build_tracking_parameters "$form_name")
payload=$(jq -nc --arg name "$form_name" --arg url "$PRIVACY_URL" --argjson tp "$tp" '{
  name: $name,
  questions: [{type:"FULL_NAME"},{type:"EMAIL"},{type:"PHONE"}],
  privacy_policy: {url: $url},
  context_card: {title:"Teste CRM", content:["Validação ponta-a-ponta"], style:"LIST_STYLE"},
  thank_you_page: {title:"Obrigado!", body:"Teste.", button_type:"NONE"},
  disqualified_thank_you_page: {title:"Obrigado!", body:"Teste.", button_type:"VIEW_ON_FACEBOOK", button_text:"Ver"},
  tracking_parameters: $tp
}')
form_resp=$(graph_api POST "${PAGE_ID}/leadgen_forms" "$payload")
test_form_id=$(echo "$form_resp" | jq -r '.id // empty')
```

`[fonte: verificado ao vivo no spike T2]` a criação funcionou com o **token de
sistema/usuário** do `.env` — não precisou de page token pra este POST (diferente da
suposição inicial do brief da Task 9; page token só é necessário depois, pra arquivar).

### Passo 2 — Disparar o test lead

```bash
graph_api POST "${test_form_id}/test_leads" '{}'
```

Retorna `{"id": "<lead_id>"}`. Dados são dummy automáticos (`<test lead: dummy data for
full_name>` etc, `email` fixo `test@meta.com` — confirmado no spike T2).

### Passo 3 — Aguardar e buscar o contato no GHL

```bash
sleep 30
r=$(ghl_api GET "/contacts/?locationId=${GHL_LOCATION_ID}&query=test@meta.com")
```

`[não verificado ao vivo — validar na T23]` formato esperado da resposta (não exercitado,
sem credencial):
```json
{"contacts": [{"id": "<contact_id>", "email": "test@meta.com", "customFields": [...]}]}
```

### Passo 4 — Conferir também o receiver

```bash
r_health=$(curl -sS --max-time 10 "$RECEIVER_HEALTH_URL" 2>/dev/null)
echo "$r_health" | jq '{received_total, pushed, errors, last_status}'
```

`last_status == "pushed"` e `received_total`/`pushed` incrementados desde antes do teste
= receiver processou o evento. Se `RECEIVER_HEALTH_URL` não responder JSON (estado atual
enquanto a rota pública não existe — ver `status` acima), reportar isso explicitamente,
não fabricar um resultado.

### Passo 5 — Veredito

```
Contato apareceu no GHL (Passo 3)?         SIM / NÃO
Campos mapeados corretos (nome/email/tel)? SIM / NÃO / PARCIAL
UTMs presentes (nativa e/ou receiver)?     NATIVA / RECEIVER / NENHUM
Receiver: last_status == pushed?           SIM / NÃO / SEM ROTA PÚBLICA

Veredito:
  NATIVA OK      → contato chegou via nativa, campos mapeados
  SÓ RECEIVER    → nativa não trouxe o contato, mas receiver empurrou (pushed)
  NADA CHEGOU    → nem nativa nem receiver — diagnosticar (ver abaixo)
```

Diagnóstico se `NADA CHEGOU`:
- GHL sem mapeamento do form (rodar `mapear {form_id}` primeiro)
- Receiver sem rota pública (ver `status`, check 2)
- `META_APP_SECRET` do receiver ainda placeholder (webhook rejeita com 403 antes de
  processar — ver `webhook-receiver/deploy/RUNBOOK.md` §10)
- Página não subscrita em `leadgen` (ver `status`, check 3)

### Passo 6 — Archive do form de teste (sempre, mesmo em erro)

Lead gen forms **não suportam DELETE** via Graph API (`error_subcode 33`, confirmado no
spike T2 e em `tests/08-lead-forms.sh::_cleanup_forms`). Arquivar via `status=ARCHIVED`
**com page token** (não o token de sistema/usuário):

```bash
page_token=$(GRAPH_API_SKIP_RESOLVER=1 graph_api GET "${PAGE_ID}?fields=access_token" 2>/dev/null \
  | jq -r '.access_token // empty')
if [[ -n "$page_token" ]]; then
  curl -sS -X POST "https://graph.facebook.com/${META_API_VERSION:-v25.0}/${test_form_id}" \
    -d "status=ARCHIVED" -d "access_token=${page_token}"
else
  echo "⚠ sem page token — arquive manualmente: ${test_form_id}"
fi
```

Rodar isso num `trap ... EXIT` (mesmo padrão de `tests/08-lead-forms.sh`), pra arquivar
mesmo se o teste abortar no meio.

## Modo `capi-setup` — ver T12

Stub. A Task 12 preenche setup do dataset de Conversions API do funil (associação
dataset↔pixel, configuração da ação nativa do GHL que dispara CAPI). Nenhum conteúdo aqui
até lá — não inventar payload/endpoint antes da Task 12 verificar.

## Modo `capi-testar` — ver T12

Stub. A Task 12 preenche disparo de test event + verificação no Test Events do Events
Manager (`CAPI_TEST_EVENT_CODE`). Nenhum conteúdo aqui até lá.

## Regras invioláveis

1. **Nunca ecoar `GHL_PIT_TOKEN` nem `META_ACCESS_TOKEN`** — nem em log, nem em `set -x`,
   nem em mensagem de erro (só o `length`, se precisar confirmar que existe).
2. **Test lead só em form `TEST_`** criado por este flow, ou com confirmação explícita do
   usuário se for reusar um form existente (nunca dispara silenciosamente em form de
   produção).
3. **`test_leads` tem limite de 1 por form** — sempre form novo por rodada de teste
   (Passo 1 do modo `testar`).
4. **Forms de teste são arquivados, nunca deletados** (Graph API não suporta DELETE em
   `leadgen_forms`) — sempre via `status=ARCHIVED` com **page token**, nunca com o token
   de sistema/usuário.
5. **Payload de resposta do GHL não exercitado ao vivo** fica rotulado
   `[não verificado ao vivo — validar na T23]` — não tratar como contrato fechado até lá.
6. **`GHL_PIT_TOKEN` nunca vai pro `CLAUDE.md`** — só `.env`.

## Ganchos com outras skills

- **`flows/lead-forms/`** — dono do `form_id` e do `tracking_parameters` que a nativa GHL
  e o receiver consomem; `testar` usa o mesmo payload mínimo validado lá.
- **`flows/doctor/`** — pre-flight de token/scopes/rate-limit antes de rodar `status`; a
  Task 21 formaliza `check_ghl`/`check_receiver`/`check_leadgen_subscription` em
  `lib/preflight.sh`, reusando os corpos deste doc.
- **`flows/setup/`** — Passo 8.5 coleta `GHL_LOCATION_ID`/`GHL_PIT_TOKEN`/
  `RECEIVER_HEALTH_URL` (spec completa no plano v1.1, Task 21 Step 2).
- **`webhook-receiver/`** — `config.json` (Passo 3 do modo `mapear`) e `/meta-leads/health`
  (checks 2 do modo `status` e Passo 4 do modo `testar`).
- **`lib/graph_api.sh`** — todo GET/POST na Meta passa por ele (retry + error-resolver);
  chamadas ao GHL usam o `ghl_api()` inline deste flow, e chamadas que exigem page token
  usam `curl` direto (mesma exceção documentada em `lib/rollback.sh:80` e
  `tests/08-lead-forms.sh::_cleanup_forms`).
