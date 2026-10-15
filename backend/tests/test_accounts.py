from datetime import datetime, timedelta, timezone
import os
import secrets
import pytest
import mongomock
from fastapi.testclient import TestClient
from account_api import app, database, lifespan, token_digest
from pymongo import MongoClient


@pytest.fixture
def api():
    uri = os.environ.get("TEST_MONGODB_URI")
    connection = MongoClient(uri, tz_aware=True) if uri else mongomock.MongoClient(tz_aware=True)
    test_database = "pcosense_test_" + secrets.token_hex(8)
    db = connection[test_database]
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
        # Delete only this fixture's randomly named, isolated test database.
        assert test_database.startswith("pcosense_test_")
        connection.drop_database(test_database)
        connection.close()


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


def test_auth_rate_limit_and_health(api, monkeypatch):
    client, _ = api
    monkeypatch.setenv("AUTH_RATE_LIMIT", "2")
    credentials = {"email": "missing@example.com", "password": "wrong password"}
    assert client.post("/auth/login", json=credentials).status_code == 401
    assert client.post("/auth/login", json=credentials).status_code == 401
    blocked = client.post("/auth/login", json=credentials)
    assert blocked.status_code == 429
    assert int(blocked.headers["Retry-After"]) > 0
    assert client.get("/health").status_code == 200


def test_passwordless_guest_devices_are_isolated(api):
    client, db = api
    first = client.post('/auth/guest', json={'key': 'a' * 43}).json()
    again = client.post('/auth/guest', json={'key': 'a' * 43}).json()
    second = client.post('/auth/guest', json={'key': 'b' * 43}).json()
    assert first['user']['uid'] == again['user']['uid']
    assert first['user']['uid'] != second['user']['uid']
    a = {'Authorization': 'Bearer ' + first['access_token']}
    b = {'Authorization': 'Bearer ' + second['access_token']}
    assert client.patch('/me', headers=a, json={'hasPCOS': True}).status_code == 200
    assert 'hasPCOS' not in client.get('/me', headers=b).json()
    stored = db.users.find_one({'_id': first['user']['uid']})
    assert 'passwordHash' not in stored
    assert client.post('/auth/login', json={'email': stored['email'], 'password': 'anything long'}).status_code == 401


def test_recovery_is_single_use_and_revokes_all_sessions(api, monkeypatch):
    import account_api
    from account_api import new_session
    client, db = api
    _, headers = register(client)
    before_reset = db.users.find_one()
    sent = []
    monkeypatch.setenv("SMTP_HOST", "mail.example.com")
    monkeypatch.setenv("SMTP_FROM", "app@example.com")
    monkeypatch.setattr(account_api, "send_recovery_email", lambda email, token: sent.append((email, token)))
    unknown = client.post("/auth/forgot-password", json={"email": "unknown@example.com"})
    known = client.post("/auth/forgot-password", json={"email": "TEST@EXAMPLE.COM"})
    assert unknown.json() == known.json()
    assert len(sent) == 1
    token = sent[0][1]
    assert db.users.find_one()["passwordResetHash"] == token_digest(token)
    assert token not in known.text
    assert client.post("/auth/reset-password", json={"token": token, "password": "new secure password"}).status_code == 200
    assert client.get("/me", headers=headers).status_code == 401
    assert client.post("/auth/reset-password", json={"token": token, "password": "another password"}).status_code == 400
    assert client.post("/auth/login", json={"email": "test@example.com", "password": "a secure password"}).status_code == 401
    assert client.post("/auth/login", json={"email": "test@example.com", "password": "new secure password"}).status_code == 200
    # Even a login that read the old password immediately before reset is rejected.
    stale = new_session(db, before_reset)
    assert client.get("/me", headers={"Authorization": "Bearer " + stale["access_token"]}).status_code == 401


def test_recovery_expiry_missing_transport_and_mail_failure(api, monkeypatch):
    import account_api
    client, db = api
    register(client)
    monkeypatch.delenv("SMTP_HOST", raising=False)
    assert client.post("/auth/forgot-password", json={"email": "test@example.com"}).status_code == 503
    monkeypatch.setenv("SMTP_HOST", "mail.example.com")
    monkeypatch.setenv("SMTP_FROM", "app@example.com")
    sent = []
    monkeypatch.setattr(account_api, "send_recovery_email", lambda email, token: sent.append(token))
    client.post("/auth/forgot-password", json={"email": "test@example.com"})
    db.users.update_one({}, {"$set": {"passwordResetExpiresAt": datetime.now(timezone.utc) - timedelta(seconds=1)}})
    assert client.post("/auth/reset-password", json={"token": sent[0], "password": "new password"}).status_code == 400
    def fail(*args):
        raise OSError("Mail unavailable")
    monkeypatch.setattr(account_api, "send_recovery_email", fail)
    result = client.post("/auth/forgot-password", json={"email": "test@example.com"})
    assert result.status_code == 200
    assert "passwordResetHash" not in db.users.find_one()


def test_onboarding_cannot_clear_required_fields(api):
    client, _ = api
    _, headers = register(client)
    profile = {"lastPeriodStartDate": "2026-10-01", "averagePeriodDuration": 5,
               "typicalCycleLength": 30, "onboardingComplete": True}
    assert client.patch("/me", headers=headers, json=profile).status_code == 200
    assert client.patch("/me", headers=headers, json={"typicalCycleLength": None}).status_code == 422


def test_session_validation_in_separate_food_app(api):
    from fastapi import Depends, FastAPI
    from account_api import current_user
    client, db = api
    _, headers = register(client)
    food_app = FastAPI()
    food_app.dependency_overrides[database] = lambda: db
    @food_app.get("/food")
    def food(user=Depends(current_user)):
        return {"email": user["email"]}
    with TestClient(food_app) as food_client:
        assert food_client.get("/food").status_code == 401
        assert food_client.get("/food", headers=headers).json()["email"] == "test@example.com"
        client.post("/auth/logout", headers=headers)
        assert food_client.get("/food", headers=headers).status_code == 401


def test_actual_food_routes_require_session_and_validate_input(api, monkeypatch):
    pytest.importorskip("chromadb")
    import main
    import main2
    client, db = api
    _, headers = register(client)
    async def no_ingredients(text):
        return []
    async def no_dish(name):
        return {"ingredients_data": [], "total_ingredients": 0}
    monkeypatch.setattr(main, "call_llm_for_ingredient_extraction", no_ingredients)
    monkeypatch.setattr(main2, "get_dish_ingredients_and_attributes", no_dish)
    for food_app in (main.app, main2.app):
        food_app.dependency_overrides[database] = lambda: db
    try:
        packed = TestClient(main.app)
        cooked = TestClient(main2.app)
        assert packed.post("/extract_ingredients", json={"text": "oats"}).status_code == 401
        assert packed.post("/extract_ingredients", headers=headers, json={"text": "x" * 20001}).status_code == 422
        assert packed.post("/extract_ingredients", headers=headers, json={"text": "oats"}).status_code == 400
        def upload(auth=None, name="rice", content=b"image"):
            return cooked.post("/upload_food_data/", headers=auth,
                data={"dish_name": name}, files={"file": ("food.jpg", content, "image/jpeg")})
        assert upload().status_code == 401
        assert upload(headers, "   ").status_code == 422
        assert upload(headers, content=b"x" * (10 * 1024 * 1024 + 1)).status_code == 413
        assert upload(headers).status_code == 404
        packed.close()
        cooked.close()
    finally:
        main.app.dependency_overrides.clear()
        main2.app.dependency_overrides.clear()


@pytest.mark.skipif(not os.environ.get("TEST_MONGODB_URI"), reason="Real MongoDB not requested")
def test_real_startup_creates_indexes(monkeypatch):
    db_name = "pcosense_test_" + secrets.token_hex(8)
    monkeypatch.setenv("MONGODB_URI", os.environ["TEST_MONGODB_URI"])
    monkeypatch.setenv("MONGODB_DATABASE", db_name)
    try:
        with TestClient(app) as client:
            assert client.get("/health").json()["storage"] == "mongodb"
            assert app.state.db.users.index_information()["email_1"]["unique"] is True
            assert app.state.db.sessions.index_information()["expiresAt_1"]["expireAfterSeconds"] == 0
            assert app.state.db.rateLimits.index_information()["expiresAt_1"]["expireAfterSeconds"] == 0
            register(client)
    finally:
        with MongoClient(os.environ["TEST_MONGODB_URI"]) as connection:
            assert db_name.startswith("pcosense_test_")
            connection.drop_database(db_name)
