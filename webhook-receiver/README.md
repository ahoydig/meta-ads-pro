# webhook-receiver

App FastAPI que recebe o webhook de **leadgen** da Meta (Facebook/Instagram Lead Ads)
e empurra o lead pro **GoHighLevel (GHL)** de cada cliente. Suporta múltiplos
clientes num único deploy, via mapa `page_id → {location_id, ghl_token_env}`.

Faz parte do Track A do plano v1.1 do `meta-ads-pro` — este diretório é a **Task 9**
(construção local, TDD). O **deploy na VPS** atrás do Cloudflare Tunnel é a **Task 10**;
o comando de saúde do plugin (`doctor`, Task 21) consome o `/meta-leads/health` daqui.

## Visão geral do fluxo

1. Meta manda `POST /meta-leads` só com o `leadgen_id` (o payload do webhook **não**
   traz nome/e-mail/telefone — confirmado no spike T4).
2. O receiver confere a assinatura HMAC (`X-Hub-Signature-256`) contra o `META_APP_SECRET`.
3. Busca os dados completos do lead na Graph API: `GET /{leadgen_id}?fields=id,created_time,field_data,ad_id,adset_id,campaign_id,form_id`.
4. Resolve o cliente (`location_id` + token do GHL) pelo `page_id` do evento, olhando o
   config JSON.
5. Empurra o lead pro GHL (`POST /contacts/upsert`), com dedup por `leadgen_id` (arquivo
   `seen_leadgen_ids.txt` no `RECEIVER_STATE_DIR`, escrito de forma atômica via tmp +
   `os.replace`) — evita duplicar contato se a Meta reenviar o mesmo evento.
6. Loga cada evento em `events.jsonl` (`RECEIVER_STATE_DIR`); `GET /meta-leads/health`
   resume esse log (total + contadores por status + último evento).

## Semântica de retry (lead nunca se perde em falha transiente)

| Situação | seen? | Resposta | Efeito |
|---|---|---|---|
| Lead buscado e empurrado pro GHL | sim | `200` | Fluxo normal (`status: pushed`). |
| `fetch_lead`/`push_to_ghl` falhou (Graph/GHL fora, rede) | **não** | **`500`** | A Meta reenvia o evento com backoff automático — esse é o mecanismo de retry. Log com `status: error:...` e `will_retry: true`. Leads já pushed no mesmo payload não duplicam na reentrega (dedup). |
| `page_id` sem entrada no config (`no_config`) | sim | `200` | Página não onboarded — redelivery infinito não ajuda. O doctor (Task 21) alerta pelo contador `no_config` do `/health`. |
| Payload malformado (mas com assinatura válida — anomalia) | — | `200` | Retry não conserta malformação. Log com `status: malformed`. |
| Assinatura inválida | — | `403` | Rejeitado antes de qualquer processamento. |

## Constraint HARD: single worker

O dedup é por arquivo (`seen_leadgen_ids.txt`) e **não suporta multi-processo**. O
serviço DEVE rodar com **um único worker**: `uvicorn app:app` **sem `--workers`** (o
default é 1). A Task 10 (deploy/systemd) precisa manter essa constraint no unit file
— se um dia precisar de mais throughput, o dedup tem que migrar pra um store com lock
(SQLite/Redis) antes de subir workers.

## Nota importante: UTMs chegam junto com os dados do lead

O spike T2 provou que os `tracking_parameters` configurados no formulário de lead ads
**propagam pro `field_data`** do lead — ou seja, quando a Graph API devolve o lead, os
campos de UTM (`utm_campaign`, `utm_source`, etc.) aparecem **no mesmo array** de
`field_data`, junto com `full_name`, `email`, `phone_number`. Não existe um bloco
separado de UTMs no payload.

Por isso, `cfg["custom_fields"]` (no config JSON de cada cliente) pode mapear direto do
`field_data` (`fd`) sem transformação — a chave é o nome do `tracking_parameter` como
configurado no form, o valor é o ID do custom field correspondente no GHL. Ver
`config.example.json`.

## Rotas

| Rota | Método | Uso |
|---|---|---|
| `/meta-leads` | `GET` | Verificação do webhook (handshake `hub.mode`/`hub.verify_token`/`hub.challenge` da Meta). |
| `/meta-leads` | `POST` | Recebe os eventos de leadgen, valida assinatura, busca o lead, empurra pro GHL. `500` em falha transiente (ver semântica de retry acima). |
| `/meta-leads/health` | `GET` | Health check — `{"received_total": N, "pushed": N, "errors": N, "no_config": N, "malformed": N, "last_event_at": ..., "last_status": ...}`, tudo derivado do `events.jsonl`. Consumido pelo `doctor` (Task 21). |

## Variáveis de ambiente

Nenhum valor real vai neste repositório — só os **nomes** das env vars. Em produção
(Task 10) elas vivem num `.env` fora do git, na VPS.

| Variável | Obrigatória | Descrição |
|---|---|---|
| `META_VERIFY_TOKEN` | sim | Token arbitrário definido por você no App da Meta, usado no handshake `GET /meta-leads`. |
| `META_APP_SECRET` | sim | App Secret do app da Meta — usado pra validar a assinatura HMAC SHA-256 dos eventos (`X-Hub-Signature-256`). |
| `META_ACCESS_TOKEN` | sim | Token de acesso (page/system user) com permissão `leads_retrieval`, usado no `fetch_lead` (Graph API). |
| `META_API_VERSION` | não (default `v25.0`) | Versão da Graph API. |
| `RECEIVER_CONFIG` | não (default `config.json`) | Caminho do JSON de mapa multi-cliente `page_id → {location_id, ghl_token_env, custom_fields}`. Ver `config.example.json`. |
| `RECEIVER_STATE_DIR` | não (default `/var/lib/meta-leads`) | Diretório com o dedup (`seen_leadgen_ids.txt`) e o log de eventos (`events.jsonl`). |
| `GHL_TOKEN_<CLIENTE>` | sim, uma por cliente | Token do GHL (Private Integration ou similar) referenciado pelo `ghl_token_env` de cada entrada do config. Nome livre — quem decide é o config JSON. |

## Config multi-cliente (`config.json`, a partir de `config.example.json`)

Cada chave do JSON é o `page_id` da página do Facebook associada ao formulário de lead
ads daquele cliente. O valor tem:

- `location_id`: o location ID do GHL (subconta) do cliente.
- `ghl_token_env`: nome da env var que guarda o token do GHL daquele cliente
  (permite um token por cliente, sem misturar credenciais).
- `custom_fields` (opcional): mapa `nome_do_campo_no_lead → ID do custom field no GHL`
  — cobre tanto campos normais do form (ex.: um campo customizado do form) quanto os
  UTMs propagados via `tracking_parameters` (ver seção acima). Preenchido de fato na
  Task 11 Step 3, quando os custom fields existirem no GHL de cada cliente.

## Rodando local (dev/test)

```bash
cd webhook-receiver
python3 -m venv .venv
.venv/bin/pip install fastapi uvicorn httpx pytest
.venv/bin/pytest -q          # 9 testes, tudo com monkeypatch (sem chamada real à Meta/GHL)
```

Pra subir localmente com env fake (smoke test, sem integração real):

```bash
# ATENÇÃO: sempre SEM --workers (single worker — ver constraint acima).
META_VERIFY_TOKEN=vtoken-dev META_APP_SECRET=secret-dev META_ACCESS_TOKEN=EAAdev \
RECEIVER_CONFIG=config.example.json RECEIVER_STATE_DIR=/tmp/receiver-dev \
.venv/bin/uvicorn app:app --port 8000

curl http://127.0.0.1:8000/meta-leads/health
```

## Segurança

- Nenhum token real neste diretório. `.venv/` e `.env` estão no `.gitignore` da raiz do
  repo.
- A assinatura HMAC (`X-Hub-Signature-256`) é obrigatória em todo `POST` — eventos sem
  assinatura válida tomam `403`.
- O dedup por `leadgen_id` evita reprocessar (e reenviar pro GHL) o mesmo lead em caso
  de reentrega da Meta; em falha transiente o lead NÃO entra no dedup e o `500` faz a
  Meta reenviar — lead não se perde.
