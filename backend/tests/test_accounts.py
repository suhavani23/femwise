from datetime import datetime, timedelta, timezone
import pytest
import mongomock
from fastapi.testclient import TestClient
from account_api import app, database, lifespan, token_digest


@pytest.fixture
def api():
    db = mongomock.MongoClient(tz_aware=True).femwise
    db.users.create_index("email", unique=True)
    db.sessions.create_index("expiresAt", expireAfterSeconds=0)
    app.dependency_overrides[database] = lambda: db
    # No lifespan here: tests exercise routes with an isolated MongoDB mock.
    client = TestClient(app, raise_server_exceptions=True)
    try:
        yield client, db
    finally:
        client.close()
        app.dependency_overrides.clear()


def register(client, email="test@example.com"):
    response = client.post("/auth/register", json={
        "name": "Test", "email": email, "password": "a secure password",
    })
    assert response.status_code == 201, response.text
    data = response.json()
    return data, {"Authorization": f"Bearer {data['access_token']}"}


def test_registration_login_logout_and_password_storage(api):
    client, db = api
    data, headers = register(client, "TEST@EXAMPLE.COM")
    stored = db.users.find_one()
    assert stored["email"] == "test@example.com"
    assert stored["passwordHash"].startswith("$argon2")
    assert "password" not in stored
    assert db.sessions.find_one()["_id"] == token_digest(data["access_token"])
    assert "passwordHash" not in client.get("/me", headers=headers).text
    assert client.post("/auth/register", json={
        "name": "Another", "email": "test@example.com", "password": "long password",
    }).status_code == 409
    assert client.post("/auth/login", json={
        "email": "test@example.com", "password": "wrong password",
    }).status_code == 401
    login = client.post("/auth/login", json={
        "email": "test@example.com", "password": "a secure password",
    })
    assert login.status_code == 200
    assert client.post("/auth/logout", headers=headers).status_code == 204
    assert client.get("/me", headers=headers).status_code == 401


def test_auth_required_expiry_and_account_isolation(api):
    client, db = api
    assert client.get("/me").status_code == 401
    assert client.patch("/me", json={"hasPCOS": True}).status_code == 401
    data, a = register(client, "a@example.com")
    _, b = register(client, "b@example.com")
    assert client.patch("/me", headers=a, json={"hasPCOS": True}).status_code == 200
    assert client.get("/me", headers=a).json()["hasPCOS"] is True
    assert "hasPCOS" not in client.get("/me", headers=b).json()
    db.sessions.update_one({"_id": token_digest(data["access_token"])}, {"$set": {
        "expiresAt": datetime.now(timezone.utc) - timedelta(seconds=1),
    }})
    assert client.get("/me", headers=a).status_code == 401


def log_body():
    return {"log": {
        "date": "2026-10-15", "notes": "some notes", "isOnPeriod": True,
        "mood": "Neutral", "periodFlow": "Light", "menstrualDay": 1,
        "symptoms": {"cramps": True}, "cervicalMucus": "N/A",
        "opkResult": "N/A", "intercourseToday": False,
    }, "profile": {
        "currentCycleStatus": "ON_PERIOD", "lastPeriodStartDate": "2026-10-15",
    }}


def test_onboarding_daily_log_upsert_and_isolation(api):
    client, db = api
    data, a = register(client, "a@example.com")
    _, b = register(client, "b@example.com")
    profile = {"lastPeriodStartDate": "2026-10-01", "averagePeriodDuration": 5,
               "typicalCycleLength": 30, "onboardingComplete": True}
    assert client.patch("/me", headers=a, json=profile).status_code == 200
    path = "/me/daily-logs/2026-10-15"
    assert client.get(path, headers=a).status_code == 404
    body = log_body()
    assert client.put(path, headers=a, json=body).status_code == 200
    body["log"]["notes"] = "updated notes"
    assert client.put(path, headers=a, json=body).status_code == 200
    assert client.get(path, headers=a).json()["notes"] == "updated notes"
    assert client.get(path, headers=b).status_code == 404
    result = client.get("/me", headers=a).json()
    assert result["lastPeriodStartDate"] == "2026-10-15"
    assert result["currentCycleStatus"] == "ON_PERIOD"
    assert result["typicalCycleLength"] == 30
    assert "dailyLogs" not in result
    assert len(db.users.find_one({"_id": data["user"]["uid"]})["dailyLogs"]) == 1


def test_invalid_inputs_do_not_change_stored_data(api):
    client, db = api
    _, headers = register(client)
    for payload in [{"passwordHash": "injected"}, {"typicalCycleLength": -1},
                    {"onboardingComplete": True}, {"email": "other@example.com"}]:
        assert client.patch("/me", headers=headers, json=payload).status_code == 422
    for email in ["invalid", "x@@example.com", "x@ example.com"]:
        assert client.post("/auth/login", json={
            "email": email, "password": "long password",
        }).status_code == 422
    assert client.get("/me/daily-logs/not-a-date", headers=headers).status_code == 422
    body = log_body()
    assert client.put("/me/daily-logs/2026-10-16", headers=headers, json=body).status_code == 422
    body["profile"]["currentCycleStatus"] = "NOT_PERIOD"
    assert client.put("/me/daily-logs/2026-10-15", headers=headers, json=body).status_code == 422
    assert "dailyLogs" not in db.users.find_one()


@pytest.mark.asyncio
async def test_startup_requires_connection_configuration(monkeypatch):
    monkeypatch.delenv("MONGODB_URI", raising=False)
    with pytest.raises(RuntimeError, match="MONGODB_URI"):
        async with lifespan(app):
            pass
