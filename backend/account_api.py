"""MongoDB account/profile service, independent of the food AI dependencies."""

from contextlib import asynccontextmanager
from datetime import date, datetime, timedelta, timezone
import hashlib
import os
import secrets
from typing import Literal

from fastapi import Depends, FastAPI, HTTPException, Response
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel, ConfigDict, Field, field_validator
from pwdlib import PasswordHash
from pymongo import MongoClient, ReturnDocument
from pymongo.errors import DuplicateKeyError

password_hash = PasswordHash.recommended()
# Verify unknown accounts against a real hash to avoid a fast account-existence path.
dummy_hash = password_hash.hash(secrets.token_urlsafe(32))
bearer = HTTPBearer(auto_error=False)


def now():
    return datetime.now(timezone.utc)


@asynccontextmanager
async def lifespan(app):
    uri = os.environ.get("MONGODB_URI")
    if not uri:
        raise RuntimeError("Set MONGODB_URI before starting the account API")
    client = MongoClient(uri, serverSelectionTimeoutMS=5000, tz_aware=True)
    try:
        client.admin.command("ping")
        db = client[os.environ.get("MONGODB_DATABASE", "femwise")]
        db.users.create_index("email", unique=True)
        db.sessions.create_index("expiresAt", expireAfterSeconds=0)
        app.state.db = db
        yield
    finally:
        client.close()


app = FastAPI(title="FemWise accounts (MongoDB)", lifespan=lifespan)


@app.middleware("http")
async def private_responses(request, call_next):
    response = await call_next(request)
    response.headers["Cache-Control"] = "no-store"
    return response


def database():
    return app.state.db


class Input(BaseModel):
    model_config = ConfigDict(extra="forbid")


class Credentials(Input):
    email: str = Field(min_length=3, max_length=254)
    password: str = Field(min_length=8, max_length=128)

    @field_validator("email")
    @classmethod
    def normalize_email(cls, value):
        value = value.strip().lower()
        if value.count("@") != 1 or any(c.isspace() for c in value):
            raise ValueError("Invalid email address")
        local, domain = value.split("@")
        if not local or "." not in domain or domain.startswith(".") or domain.endswith("."):
            raise ValueError("Invalid email address")
        return value


class Registration(Credentials):
    name: str = Field(min_length=1, max_length=100)

    @field_validator("name")
    @classmethod
    def clean_name(cls, value):
        if not value.strip():
            raise ValueError("Name is required")
        return value.strip()


class ProfilePatch(Input):
    lastPeriodStartDate: date | None = None
    averagePeriodDuration: int | None = Field(default=None, ge=1, le=60)
    typicalCycleLength: int | None = Field(default=None, ge=1, le=365)
    hasPCOS: bool | None = None
    reproductiveCategory: int | None = Field(default=None, ge=0, le=9)
    generalUnusualBleeding: bool | None = None
    onboardingComplete: bool | None = None


class Symptoms(Input):
    fatigue: bool = False
    acne: bool = False
    cramps: bool = False
    headache: bool = False
    bloating: bool = False


class DailyLog(Input):
    date: date
    notes: str = Field(default="", max_length=10000)
    isOnPeriod: bool
    mood: str = Field(max_length=100)
    periodFlow: str = Field(max_length=100)
    menstrualDay: int | None = Field(default=None, ge=1, le=365)
    symptoms: Symptoms = Field(default_factory=Symptoms)
    cervicalMucus: str = Field(max_length=100)
    opkResult: str = Field(max_length=100)
    intercourseToday: bool = False


class CycleUpdate(Input):
    lastPeriodStartDate: date | None = None
    currentCycleStatus: Literal["ON_PERIOD", "NOT_PERIOD"]


class LogWrite(Input):
    log: DailyLog
    profile: CycleUpdate


def public_user(user):
    return {"uid": user["_id"], "email": user["email"], "name": user["name"]}


def public_profile(user):
    return {**user.get("profile", {}), **public_user(user)}


def token_digest(token):
    return hashlib.sha256(token.encode()).hexdigest()


def new_session(db, user):
    token = secrets.token_urlsafe(48)
    expires = now() + timedelta(days=7)
    db.sessions.insert_one({
        "_id": token_digest(token), "userId": user["_id"], "expiresAt": expires,
    })
    return {"access_token": token, "token_type": "bearer", "user": public_user(user)}


def current_user(credentials: HTTPAuthorizationCredentials | None = Depends(bearer),
                 db=Depends(database)):
    unauthorized = HTTPException(401, "Session expired. Please sign in again.",
                                 headers={"WWW-Authenticate": "Bearer"})
    if credentials is None:
        raise unauthorized
    session = db.sessions.find_one({
        "_id": token_digest(credentials.credentials), "expiresAt": {"$gt": now()},
    })
    if not session:
        raise unauthorized
    user = db.users.find_one({"_id": session["userId"]}, {"dailyLogs": 0})
    if user is None:
        raise unauthorized
    return user


@app.get("/health")
def health(db=Depends(database)):
    db.command("ping")
    return {"status": "ok", "storage": "mongodb"}


@app.post("/auth/register", status_code=201)
def register(body: Registration, db=Depends(database)):
    user = {
        "_id": secrets.token_hex(16), "email": body.email, "name": body.name,
        "passwordHash": password_hash.hash(body.password),
        "profile": {"onboardingComplete": False, "currentCycleStatus": "NOT_PERIOD",
                    "createdAt": now().isoformat()},
    }
    try:
        db.users.insert_one(user)
    except DuplicateKeyError:
        raise HTTPException(409, "An account already exists for that email.")
    return new_session(db, user)


@app.post("/auth/login")
def login(body: Credentials, db=Depends(database)):
    user = db.users.find_one({"email": body.email}, {"dailyLogs": 0})
    valid = password_hash.verify(body.password, user["passwordHash"] if user else dummy_hash)
    if not user or not valid:
        raise HTTPException(401, "Invalid email or password.")
    return new_session(db, user)


@app.post("/auth/logout", status_code=204)
def logout(user=Depends(current_user), credentials=Depends(bearer), db=Depends(database)):
    db.sessions.delete_one({"_id": token_digest(credentials.credentials)})
    return Response(status_code=204)


@app.get("/me")
def get_profile(user=Depends(current_user)):
    return public_profile(user)


@app.patch("/me")
def update_profile(body: ProfilePatch, user=Depends(current_user), db=Depends(database)):
    changes = body.model_dump(mode="json", exclude_unset=True)
    if changes.get("onboardingComplete") is True:
        merged = {**user.get("profile", {}), **changes}
        if not all(merged.get(k) is not None for k in (
                "lastPeriodStartDate", "averagePeriodDuration", "typicalCycleLength")):
            raise HTTPException(422, "Period date, duration and cycle length are required.")
    changes["updatedAt"] = now().isoformat()
    updated = db.users.find_one_and_update(
        {"_id": user["_id"]}, {"$set": {f"profile.{k}": v for k, v in changes.items()}},
        projection={"dailyLogs": 0}, return_document=ReturnDocument.AFTER,
    )
    return public_profile(updated)


@app.get("/me/daily-logs/{day}")
def get_log(day: date, user=Depends(current_user), db=Depends(database)):
    key = day.isoformat()
    result = db.users.find_one({"_id": user["_id"]}, {f"dailyLogs.{key}": 1})
    log = result.get("dailyLogs", {}).get(key)
    if log is None:
        raise HTTPException(404, "No log for this date.")
    return log


@app.put("/me/daily-logs/{day}")
def save_log(day: date, body: LogWrite, user=Depends(current_user), db=Depends(database)):
    if body.log.date != day:
        raise HTTPException(422, "Log date must match the URL date.")
    expected_status = "ON_PERIOD" if body.log.isOnPeriod else "NOT_PERIOD"
    if body.profile.currentCycleStatus != expected_status:
        raise HTTPException(422, "Cycle status must match the daily log.")
    if body.profile.lastPeriodStartDate is not None and (
            not body.log.isOnPeriod or body.log.menstrualDay != 1
            or body.profile.lastPeriodStartDate != day):
        raise HTTPException(422, "Period start must match a day-one period log.")
    log = body.log.model_dump(mode="json")
    log["timestamp"] = now().isoformat()
    changes = {f"dailyLogs.{day.isoformat()}": log, "profile.updatedAt": now().isoformat()}
    changes.update({f"profile.{k}": v for k, v in
                    body.profile.model_dump(mode="json", exclude_unset=True).items()})
    # One document update preserves the old batch's atomic log/profile behavior,
    # including on standalone local MongoDB (no replica-set transaction required).
    db.users.update_one({"_id": user["_id"]}, {"$set": changes})
    return log
