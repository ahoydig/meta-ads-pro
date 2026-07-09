import hashlib, hmac, json, os
os.environ["META_VERIFY_TOKEN"] = "vtoken-test"
os.environ["META_APP_SECRET"] = "secret-test"
os.environ["META_ACCESS_TOKEN"] = "EAAtest"
os.environ["RECEIVER_CONFIG"] = "config.test.json"
os.environ["RECEIVER_STATE_DIR"] = "/tmp/receiver-test"
os.environ["GHL_TOKEN_TEST"] = "x"

from fastapi.testclient import TestClient
import app as appmod

client = TestClient(appmod.app)

def _sig(body: bytes) -> str:
    return "sha256=" + hmac.new(b"secret-test", body, hashlib.sha256).hexdigest()

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

def test_health():
    r = client.get("/meta-leads/health")
    assert r.status_code == 200 and "received_total" in r.json()
