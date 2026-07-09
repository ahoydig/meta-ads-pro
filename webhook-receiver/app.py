"""Receiver de leadgen da Meta → GoHighLevel. Roda na VPS atrás do Cloudflare Tunnel."""
import hashlib, hmac, json, os, time, urllib.request, urllib.parse
from pathlib import Path
from fastapi import FastAPI, Request, Response, HTTPException

app = FastAPI()
VERIFY_TOKEN = os.environ["META_VERIFY_TOKEN"]
APP_SECRET = os.environ["META_APP_SECRET"].encode()
META_TOKEN = os.environ["META_ACCESS_TOKEN"]
API_VERSION = os.environ.get("META_API_VERSION", "v25.0")  # versão confirmada no spike T1
CONFIG = json.loads(Path(os.environ.get("RECEIVER_CONFIG", "config.json")).read_text())
STATE = Path(os.environ.get("RECEIVER_STATE_DIR", "/var/lib/meta-leads")); STATE.mkdir(parents=True, exist_ok=True)
SEEN = STATE / "seen_leadgen_ids.txt"; LOG = STATE / "events.jsonl"

def _log(rec): LOG.open("a").write(json.dumps(rec, ensure_ascii=False) + "\n")

def _save_seen(seen: set) -> None:
    # Escrita atômica: tmp no MESMO diretório + os.replace (rename atômico no mesmo fs).
    # Constraint HARD: dedup por arquivo só funciona com UM worker (uvicorn sem --workers).
    tmp = SEEN.with_suffix(".tmp")
    tmp.write_text("\n".join(sorted(seen)))
    os.replace(tmp, SEEN)

def fetch_lead(leadgen_id: str) -> dict:
    # O payload do webhook só traz o leadgen_id (spike T4) — o dado do lead em si
    # (nome, e-mail, telefone, UTMs) só existe depois deste GET na Graph API.
    fields = "id,created_time,field_data,ad_id,adset_id,campaign_id,form_id"
    url = (f"https://graph.facebook.com/{API_VERSION}/{urllib.parse.quote(leadgen_id, safe='')}"
           f"?fields={fields}&access_token={urllib.parse.quote(META_TOKEN)}")
    with urllib.request.urlopen(url, timeout=15) as r:
        return json.loads(r.read())

def push_to_ghl(lead: dict, cfg: dict) -> None:
    token = os.environ[cfg["ghl_token_env"]]
    fd = {f["name"]: f["values"][0] for f in lead.get("field_data", []) if f.get("values")}
    # O spike T2 provou que os tracking_parameters do form PROPAGAM pro field_data
    # do lead (ex.: campos "utm_campaign", "utm_source" chegam junto com full_name/
    # email/phone_number nesse mesmo array) — não existe um bloco extra de UTMs
    # separado no payload. Por isso cfg["custom_fields"] pode mapear direto de `fd`
    # (chave = nome do tracking_parameter no form, valor = ID do custom field no GHL).
    body = {
        "locationId": cfg["location_id"],
        "name": fd.get("full_name"), "email": fd.get("email"),
        "phone": fd.get("phone_number"),
        "source": "meta-leadform-webhook",
        "tags": ["meta-lead-ads"],
        # customFields: IDs reais por location, mapeados em cfg["custom_fields"]
        # (ex.: {"utm_campaign": "<CF_ID>"}). Preenchidos na Task 11 Step 3.
        "customFields": [
            {"id": cf_id, "value": str(lead.get(k) or fd.get(k) or "")}
            for k, cf_id in cfg.get("custom_fields", {}).items()
        ],
    }
    req = urllib.request.Request(
        "https://services.leadconnectorhq.com/contacts/upsert",
        data=json.dumps({k: v for k, v in body.items() if v}).encode(),
        headers={"Authorization": f"Bearer {token}", "Version": "2021-07-28",
                 "Content-Type": "application/json"}, method="POST")
    with urllib.request.urlopen(req, timeout=15) as r:
        r.read()

@app.get("/meta-leads")
def verify(request: Request):
    q = request.query_params
    if q.get("hub.mode") == "subscribe" and q.get("hub.verify_token") == VERIFY_TOKEN:
        return Response(q.get("hub.challenge", ""), media_type="text/plain")
    raise HTTPException(403)

@app.post("/meta-leads")
async def receive(request: Request):
    raw = await request.body()
    sig = request.headers.get("X-Hub-Signature-256", "")
    expected = "sha256=" + hmac.new(APP_SECRET, raw, hashlib.sha256).hexdigest()
    if not hmac.compare_digest(sig, expected):
        raise HTTPException(403)
    seen = set(SEEN.read_text().split()) if SEEN.exists() else set()
    had_error = False
    try:
        for entry in json.loads(raw).get("entry", []):
            for change in entry.get("changes", []):
                if change.get("field") != "leadgen":
                    continue
                v = change.get("value") or {}
                if not v.get("leadgen_id"):
                    _log({"t": time.time(), "status": "malformed",
                          "reason": "change leadgen sem leadgen_id"})
                    continue
                lid = str(v["leadgen_id"]); page = str(v.get("page_id", ""))
                if lid in seen:
                    continue
                cfg = CONFIG.get(page)
                if not cfg:
                    # Página não onboarded: marca seen + 200 — redelivery infinito não
                    # ajuda; o doctor alerta via contador no_config do /health.
                    seen.add(lid); _save_seen(seen)
                    _log({"t": time.time(), "leadgen_id": lid, "page_id": page, "status": "no_config"})
                    continue
                try:
                    lead = fetch_lead(lid)
                    push_to_ghl(lead, cfg)
                except Exception as e:
                    # Falha transiente (Graph/GHL fora): NÃO marca seen e responde 500
                    # no fim — a Meta reenvia com backoff em falha 5xx (é o mecanismo
                    # de retry). O dedup garante que leads já pushed no mesmo payload
                    # não duplicam na reentrega.
                    had_error = True
                    _log({"t": time.time(), "leadgen_id": lid, "page_id": page,
                          "form_id": v.get("form_id"), "status": f"error:{e}", "will_retry": True})
                    continue
                seen.add(lid); _save_seen(seen)
                _log({"t": time.time(), "leadgen_id": lid, "page_id": page,
                      "form_id": v.get("form_id"), "status": "pushed"})
    except (ValueError, AttributeError, TypeError) as e:
        # Payload malformado (mas COM assinatura válida — anomalia): 200, retry não
        # conserta malformação. Fica registrado pro doctor via contador malformed.
        _log({"t": time.time(), "status": "malformed", "reason": str(e)})
        if had_error:
            # Anomalia dupla: já havia uma falha transiente pendente de retry
            # (Graph/GHL fora) quando a malformação interrompeu o loop — não pode
            # engolir esse retry respondendo 200; a Meta precisa reentregar.
            raise HTTPException(500)
        return {"ok": True}
    if had_error:
        raise HTTPException(500)
    return {"ok": True}

@app.get("/meta-leads/health")
def health():
    lines = LOG.read_text().splitlines() if LOG.exists() else []
    counts = {"pushed": 0, "errors": 0, "no_config": 0, "malformed": 0}
    malformed_log_lines = 0
    last = None
    for line in lines:
        try:
            rec = json.loads(line)
        except ValueError:
            # Linha corrompida no events.jsonl (escrita parcial, disco cheio, etc.)
            # não pode derrubar o /health — conta à parte e segue pras próximas linhas.
            malformed_log_lines += 1
            continue
        st = rec.get("status", "")
        if st == "pushed":
            counts["pushed"] += 1
        elif st.startswith("error:"):
            counts["errors"] += 1
        elif st in ("no_config", "malformed"):
            counts[st] += 1
        last = rec
    return {"received_total": len(lines), **counts,
            "malformed_log_lines": malformed_log_lines,
            "last_event_at": last and last.get("t"),
            "last_status": last and last.get("status")}
