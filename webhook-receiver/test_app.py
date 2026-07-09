import hashlib, hmac, json, os, shutil
os.environ["META_VERIFY_TOKEN"] = "vtoken-test"
os.environ["META_APP_SECRET"] = "secret-test"
os.environ["META_ACCESS_TOKEN"] = "EAAtest"
os.environ["RECEIVER_CONFIG"] = "config.test.json"
os.environ["RECEIVER_STATE_DIR"] = "/tmp/receiver-test"
os.environ["GHL_TOKEN_TEST"] = "x"

import pytest
from fastapi.testclient import TestClient
import app as appmod

client = TestClient(appmod.app)

@pytest.fixture(autouse=True)
def _clean_state():
    # Hermeticidade: estado zerado antes de CADA teste — a suíte roda N vezes
    # seguidas sem rm manual e nenhum teste depende de resíduo de outro.
    shutil.rmtree(appmod.STATE, ignore_errors=True)
    appmod.STATE.mkdir(parents=True, exist_ok=True)
    yield

def _sig(body: bytes) -> str:
    return "sha256=" + hmac.new(b"secret-test", body, hashlib.sha256).hexdigest()

def _leadgen_body(lid: str, page: str = "PAGE_TEST") -> bytes:
    return json.dumps({"entry": [{"changes": [{"field": "leadgen", "value": {
        "leadgen_id": lid, "page_id": page, "form_id": "F1", "created_time": 1}}]}]}).encode()

def _seen() -> set:
    return set(appmod.SEEN.read_text().split()) if appmod.SEEN.exists() else set()

def test_verify_challenge():
    r = client.get("/meta-leads", params={
        "hub.mode": "subscribe", "hub.verify_token": "vtoken-test", "hub.challenge": "42"})
    assert r.status_code == 200 and r.text == "42"

def test_verify_wrong_token_403():
    r = client.get("/meta-leads", params={
        "hub.mode": "subscribe", "hub.verify_token": "errado", "hub.challenge": "42"})
    assert r.status_code == 403

def test_post_bad_signature_403():
    body = json.dumps({"entry": []}).encode()
    r = client.post("/meta-leads", content=body, headers={"X-Hub-Signature-256": "sha256=dead"})
    assert r.status_code == 403

def test_post_leadgen_pushes_to_ghl(monkeypatch):
    pushed = {}
    monkeypatch.setattr(appmod, "fetch_lead", lambda lid: {
        "id": lid, "field_data": [{"name": "full_name", "values": ["Maria"]},
                                  {"name": "email", "values": ["m@x.com"]},
                                  {"name": "phone_number", "values": ["+5591999999999"]}],
        "ad_id": "1", "campaign_id": "2"})
    monkeypatch.setattr(appmod, "push_to_ghl", lambda lead, cfg: pushed.update(lead=lead, cfg=cfg))
    body = json.dumps({"entry": [{"changes": [{"field": "leadgen", "value": {
        "leadgen_id": "L1", "page_id": "PAGE_TEST", "form_id": "F1", "created_time": 1}}]}]}).encode()
    r = client.post("/meta-leads", content=body, headers={"X-Hub-Signature-256": _sig(body)})
    assert r.status_code == 200
    assert pushed["lead"]["id"] == "L1" and pushed["cfg"]["location_id"] == "loc-test"

def test_post_dedup_same_leadgen_id(monkeypatch):
    calls = []
    monkeypatch.setattr(appmod, "fetch_lead", lambda lid: {"id": lid, "field_data": []})
    monkeypatch.setattr(appmod, "push_to_ghl", lambda lead, cfg: calls.append(lead["id"]))
    body = json.dumps({"entry": [{"changes": [{"field": "leadgen", "value": {
        "leadgen_id": "L2", "page_id": "PAGE_TEST", "form_id": "F1", "created_time": 1}}]}]}).encode()
    for _ in range(2):
        client.post("/meta-leads", content=body, headers={"X-Hub-Signature-256": _sig(body)})
    assert calls == ["L2"]

def test_post_push_failure_500_not_seen_then_retry_succeeds(monkeypatch):
    # Falha transiente no push → 500 (Meta reenvia) e lead NÃO marcado como seen.
    monkeypatch.setattr(appmod, "fetch_lead", lambda lid: {"id": lid, "field_data": []})
    def boom(lead, cfg):
        raise RuntimeError("GHL fora do ar")
    monkeypatch.setattr(appmod, "push_to_ghl", boom)
    body = _leadgen_body("L3")
    r = client.post("/meta-leads", content=body, headers={"X-Hub-Signature-256": _sig(body)})
    assert r.status_code == 500
    assert "L3" not in _seen()
    # Reentrega da Meta com o push funcionando → pushed.
    calls = []
    monkeypatch.setattr(appmod, "push_to_ghl", lambda lead, cfg: calls.append(lead["id"]))
    r = client.post("/meta-leads", content=body, headers={"X-Hub-Signature-256": _sig(body)})
    assert r.status_code == 200 and calls == ["L3"]
    assert "L3" in _seen()

def test_post_malformed_signed_200():
    # Assinatura VÁLIDA mas corpo não-JSON (anomalia): 200 — retry não conserta malformação.
    body = b"nao-e-json"
    r = client.post("/meta-leads", content=body, headers={"X-Hub-Signature-256": _sig(body)})
    assert r.status_code == 200
    assert any(json.loads(l)["status"] == "malformed" for l in appmod.LOG.read_text().splitlines())

def test_post_no_config_200_and_seen():
    # Página não onboarded: 200 + marcado seen (redelivery infinito não ajuda).
    body = _leadgen_body("L4", page="PAGE_DESCONHECIDA")
    r = client.post("/meta-leads", content=body, headers={"X-Hub-Signature-256": _sig(body)})
    assert r.status_code == 200
    assert "L4" in _seen()
    h = client.get("/meta-leads/health").json()
    assert h["no_config"] == 1

def test_health():
    r = client.get("/meta-leads/health")
    assert r.status_code == 200
    h = r.json()
    for key in ("received_total", "pushed", "errors", "no_config", "malformed"):
        assert key in h
