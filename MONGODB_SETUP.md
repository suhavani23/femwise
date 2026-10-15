# Run FemWise with MongoDB

Firebase Authentication and Firestore have been replaced by `backend/account_api.py`.
The Flutter app calls this service for registration, login, profile updates and daily logs.
MongoDB credentials belong only on the backend; never put a MongoDB URI in Flutter.

## 1. Provide a database

Use MongoDB Community Server locally (default port 27017), or a MongoDB Atlas cluster.
For Atlas, create a database user, allow the backend machine's IP in Network Access,
and copy its Python-driver connection string. URL-encode reserved password characters.
Do not expose a local MongoDB port to the internet.

The backend creates the `femwise` database and these collections on first use:

| Collection | Contents |
| --- | --- |
| `users` | Normalized unique email, name, Argon2 password hash, profile and daily logs |
| `sessions` | SHA-256 digest of a random bearer token, user ID, expiration |

Daily logs are stored under `users.dailyLogs.YYYY-MM-DD`. Updating a log and the
associated cycle status is one atomic MongoDB document update, so a standalone
development database works without a replica set. This design has MongoDB's 16 MiB
per-document limit; split logs into their own collection with transactions before
adding large log payloads or supporting unbounded histories. No images are stored here.

## 2. Start the account API

Open PowerShell in the project folder (the folder containing `pubspec.yaml`):

```powershell
cd backend
py -3.11 -m venv .venv-accounts
.\.venv-accounts\Scripts\python.exe -m pip install -r requirements-accounts.txt
Copy-Item .env.example .env
```

Edit `.env`:

```dotenv
MONGODB_URI=mongodb://127.0.0.1:27017
MONGODB_DATABASE=femwise
```

For Atlas, replace `MONGODB_URI` with your `mongodb+srv://...` URI. Then run:

```powershell
.\.venv-accounts\Scripts\python.exe -m uvicorn account_api:app --env-file .env --host 0.0.0.0 --port 8002 --reload
```

Visit <http://localhost:8002/health> and <http://localhost:8002/docs>.
Startup fails if MongoDB is unreachable. The service creates a unique email index
and a TTL index on sessions. It also checks expiration during every authenticated
request, independent of MongoDB's asynchronous TTL cleanup.

## 3. Run Flutter on Android

In another PowerShell window, from the inner project folder:

```powershell
flutter pub get
flutter analyze
flutter run --dart-define=ACCOUNT_API_URL=http://10.0.2.2:8002
```

`10.0.2.2` reaches the Windows host from the standard Android emulator. On a physical
phone, use the PC's LAN IP instead, connect to the same network, and permit port 8002
through Windows Firewall. A MongoDB URI is never the value of `ACCOUNT_API_URL`.

Debug Android builds allow local HTTP. Release builds need an HTTPS API URL.
Tokens are stored with `flutter_secure_storage`, expire after seven days, and are
revoked on successful logout. If the API cannot be reached at logout, retry after
restoring connectivity so the server can revoke the session.

Firebase configuration and Firebase console setup are no longer required.
`flutter pub get` regenerates native plugin registration after dependency changes.
The existing repo's Android wrapper/build, missing logo, and pose-package issues
still need resolving if encountered; this migration does not establish a passing
Flutter build without the Flutter SDK and Android toolchain.

## API contract

| Method | Route | Purpose |
| --- | --- | --- |
| POST | `/auth/register` | `{name, email, password}` → token and user |
| POST | `/auth/login` | `{email, password}` → token and user |
| POST | `/auth/logout` | Revoke current bearer session |
| GET | `/me` | Profile of the authenticated user |
| PATCH | `/me` | Update allowed onboarding/profile fields |
| GET | `/me/daily-logs/YYYY-MM-DD` | Fetch a day; 404 when absent |
| PUT | `/me/daily-logs/YYYY-MM-DD` | Atomically save `{log, profile}` |

Authenticated requests use `Authorization: Bearer <access_token>`. Clients cannot
choose another user ID. Profile and log input schemas reject unknown fields.
Passwords must be 8–128 characters; passwords are not trimmed. Calendar dates use
`YYYY-MM-DD`, while server-generated timestamps use UTC ISO strings.

## Existing Firebase accounts

Removing Firebase does not copy remote users or history. This checkout contains no
user export. Register new development accounts. To retain existing users, prepare
an explicit export/import process that maps old user IDs, profiles, and daily logs;
use a password-reset or separately reviewed password-hash migration strategy.
Never copy plaintext passwords. Do not delete the remote Firebase project until
the imported data and account access have been verified.

## Food analysis remains separate

Run `main:app` on port 8000 and `main2:app` on port 8001 with their own dependencies
and configured Flutter food endpoints. They still require Neo4j, Gemini, Ollama
(packaged food), and populated ChromaDB (cooked food). The account API does not
import these AI modules. Replacing Firebase does not restore their missing datasets
or update the retired Gemini model. Food endpoints retain their existing access
behavior; bearer authentication was added to the account service only.

## Verification

```powershell
cd backend
.\.venv-accounts\Scripts\python.exe -m pip install -r requirements-accounts-test.txt
.\.venv-accounts\Scripts\python.exe -m pytest tests -q
```

Tests use an isolated MongoDB mock, not your database. They cover signup, hashing,
duplicate emails, login, session expiration/revocation, user isolation, onboarding,
log overwrite behavior and invalid requests. Also verify against a real MongoDB
instance and Android device before release. Before public deployment, add TLS,
authentication rate limits, account recovery and operational monitoring/backups.
