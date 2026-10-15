# PCOSense setup and handoff

Prepared on 15 October 2026 in `E:\Team Aether\Chaos\femwise`.

## Current APK: no login required

The latest APK opens directly to the home screen in guest mode. There is no
login/signup step or logout button. Use the profile icon to enter cycle details.
Guest profiles and daily logs are saved in encrypted storage **on the phone**,
and work without the laptop or MongoDB. They are not synced to MongoDB in this
version. Clearing app data removes this local guest history.

Existing MongoDB accounts/data remain unchanged. The protected account API still
exists for legacy accounts; food services can obtain a separate, device-isolated
guest session automatically. Food analysis still requires the laptop backend and
its configured food providers/datasets. SMTP and account recovery are not needed
to use the guest app.

Latest validation: **19 backend tests passed, 2 Flutter tests passed, analyzer
clean, debug APK built successfully**. The offline storage test verifies profile
and log persistence across service initialization without making API requests.

Updated APK: `build/app/outputs/flutter-apk/pcosense-no-login.apk`.

## Completed

- Created `backend/.env` for the local `pcosense` MongoDB database. It is ignored by Git.
- Installed a project-local Python environment, account/test dependencies and optional food dependencies.
- Downloaded and checksum-verified a portable MongoDB development server in `.tools/mongodb`.
- Started MongoDB bound to `127.0.0.1:27017` and the account API at `http://127.0.0.1:8002`.
- Verified registration, login, logout, profile/onboarding and daily logs against real MongoDB.
- Added MongoDB-backed authentication attempt limits (20 attempts per IP, route and 15-minute window).
- Added password recovery: emailed single-use tokens, 20-minute expiry, hashed token storage, and invalidation of existing sessions after reset. SMTP must be configured before emails can be sent.
- Added the Flutter password recovery screen and login link.
- Added account backup/restore tooling. Backups include profiles and logs, omit sessions and reset tokens, and refuse to overwrite existing account data on restore.
- Removed embedded food-service API keys/passwords from current source and moved settings into `backend/.env`.
- Replaced the retired Gemini model integration with the Google Gen AI SDK and configurable `GEMINI_MODEL`.
- Protected both food analysis endpoints using the same account bearer sessions.
- Replaced old food IP addresses with configurable service addresses; corrected cooked food to port 8001.
- Restored the Gradle wrapper and added checksum verification for its distribution.
- Aligned Android compilation with SDK 36, Android Gradle Plugin 8.12.1, Kotlin 2.2.0 and Gradle 8.13, using project-local Java 17. Missing SDK/NDK/CMake components were installed into the existing `C:/Android/Sdk` toolchain using its accepted licenses.
- Replaced missing logo references with a reusable Flutter logo widget.
- Resolved Flutter dependency conflicts, declared imported packages and saved `pubspec.lock`.
- Fixed a missing closing brace in the app entry file and resolved all Dart analyzer findings.
- Updated pose image conversion for the current image package, fixed model/camera startup ordering, handled padded camera rows, and required a sustained pose hold. Actual camera matching still needs device testing.
- Connected the packaged-food gallery action and saved the previously discarded unusual-bleeding response in the daily log.
- Added Android cropper activity configuration and release keystore configuration. Release builds require your own keystore.
- Added startup helpers, tested Python constraints and an optional local Docker Compose configuration.
- Corrected the README: cycle estimates currently use formulas; adaptive machine learning has not been built.

## Verification

- `flutter analyze --no-pub`: **No issues found** with Flutter 3.29.3 / Dart 3.7.2, including the new test file.
- Backend suite: **16 passed**, including real MongoDB account integration, startup/index verification and actual food-route authentication/input validation. Backup and external-provider error handling have isolated unit tests.
- Flutter password recovery form test: **1 passed**.
- `pip check`: **No broken requirements found**.
- Both food-service modules import successfully. Food analysis has not been tested with live providers/datasets.
- Android debug APK compilation: **successful**, using both Gradle directly and the normal Flutter build command. Signature verification passed; the pose model is included and backend `.env` files are excluded.
- No Android device or emulator was connected during the device check.
- Docker configuration is supplied but was not run; Docker is not installed here.

## Start the local account app

Run commands from the project folder. If the services from this chat are still running, you can use their existing addresses. Otherwise use separate PowerShell windows:

```powershell
# Window 1: keep it open for the local database.
.\scripts\Start-LocalMongo.ps1
```

```powershell
# Window 2: keep it open for the API.
.\scripts\Start-Backend.ps1
```

Check [health](http://127.0.0.1:8002/health) and [interactive API documentation](http://127.0.0.1:8002/docs).

```powershell
# Window 3: start an Android emulator or attach your phone first.
.\scripts\Run-App.ps1
```

`Run-App.ps1` defaults to `10.0.2.2`, the Android emulator's address for the PC.
It uses project-local Flutter preferences to avoid changing global preferences or requiring Windows desktop plugin links.

For a physical phone, connect it to the same network as the PC, enable USB debugging, approve the phone's debugging prompt, and use the PC's LAN IP:

```powershell
.\scripts\Start-Backend.ps1 -ListenAddress 0.0.0.0
.\scripts\Run-App.ps1 -BackendHost YOUR_PC_LAN_IP
```

Stop the existing API before restarting on a different listen address. Permit the API port through your firewall for your private network if needed. MongoDB remains bound to localhost; phones connect to the API.

## Tasks requiring you

### 1. Choose a device and test the app

Connect a phone or start an emulator using Android Studio. Check this flow:

1. Open the app directly; no account is required.
2. Use the profile icon to enter cycle details if needed.
3. Save a daily log and reopen it from the calendar.
4. Close/reopen the app and verify the guest data is still present offline.
5. Try yoga/pose matching with the camera and test the food label cropper.

Pose thresholds, camera orientation and feedback quality require testing on actual hardware. They are not established by a successful analyzer result.

### 2. Cloud MongoDB — optional for local development

The local database already works. If you want shared or hosted data, create an Atlas cluster, create a database user, allow the backend's IP and replace `MONGODB_URI` in `backend/.env` with the Atlas URI. Restart the API.

The database name stays `pcosense`. Collections/indexes are created automatically. Keep the URI on the backend. See [MongoDB's connection guide](https://www.mongodb.com/docs/atlas/connect-to-database-deployment/).

### 3. Food analysis credentials and data

Provide these in `backend/.env`:

- `GEMINI_API_KEY` from your own Google AI Studio project. Set a model your account supports using `GEMINI_MODEL`.
- `NEO4J_URI`, `NEO4J_USERNAME`, `NEO4J_PASSWORD` for a Neo4j instance containing the original ingredient knowledge graph.
- `CHROMA_DB_PATH` pointing to a populated cooked-dish database with collection `cooked_dishes` (or set `CHROMA_COLLECTION`). The code expects dish metadata with `dish_name` and a JSON-encoded `ingredients` array.
- A running Ollama server with the model selected by `OLLAMA_MODEL` installed for packaged-food extraction.

The original ingredient graph and cooked-dish dataset are absent. An empty ChromaDB folder has been initialized for module validation; it is not a populated dataset. Obtain/export the original data or build a reviewed replacement dataset before using food analysis. The cooked endpoint currently uses the entered dish name; its uploaded photo is not used for visual food recognition.

**Rotate the old Gemini keys and Neo4j password with their owner if those credentials are active.** They were embedded in the original checkout and may remain in Git history. Current source no longer embeds them.

Start the configured services in separate windows:

```powershell
.\scripts\Start-Backend.ps1 -Service packaged
.\scripts\Start-Backend.ps1 -Service cooked
```

Ports: packaged food 8000, cooked food 8001, accounts 8002. All services must use the same MongoDB database for session validation.

### 4. Recovery email

Set `SMTP_HOST`, `SMTP_PORT`, `SMTP_SECURITY` (`starttls` or `ssl`), `SMTP_FROM`, and your provider's `SMTP_USERNAME` / `SMTP_PASSWORD`. Use provider-issued credentials. Restart the account API and test email delivery.

Until configured, requesting recovery returns a clear service-unavailable message. Tests validate the recovery flow without sending real emails.

### 5. Publishing and existing users

- Choose hosting and a domain; deploy the backend with HTTPS, restricted database access, monitoring and scheduled backups. No public deployment has been performed.
- Generate your upload keystore, copy `android/key.properties.example` to the ignored `android/key.properties`, and fill it in. Choose the final app ID and store details before publishing. Release builds no longer silently use the debug key.
- Existing Firebase users/history have not been migrated: no export was supplied. New development accounts work independently. Retaining old accounts requires an export/import and a reviewed password migration/reset process.
- Adaptive cycle machine learning and visual cooked-food recognition remain future product work; adding MongoDB does not implement them.

## Repeat checks and backups

```powershell
.\scripts\Flutter.ps1 analyze --no-pub

# Run with the local server. Tests use randomly named temporary databases.
$env:TEST_MONGODB_URI = 'mongodb://127.0.0.1:27017'
Push-Location backend
.\.venv-accounts\Scripts\python.exe -m pytest tests -q
Pop-Location

.\backend\.venv-accounts\Scripts\python.exe backend\backup_accounts.py backup
```

Backups are saved in the ignored `backups/` folder and contain sensitive account/health data. Keep copies in private storage. This is a per-account export, not a coordinated whole-cluster snapshot. For hosted use, configure provider backups and test restoration.

To restore an export into an empty database:

```powershell
.\backend\.venv-accounts\Scripts\python.exe backend\backup_accounts.py restore --file backups\YOUR_BACKUP.bson --database pcosense_restored
```

Point `MONGODB_DATABASE` at the restored database only after checking it. Never delete an existing database to make room for a restore.

Daily logs are embedded in user documents. Before supporting unbounded/large histories, redesign storage around MongoDB's per-document size limit.

## Android build result

Verified successfully. Built `build\app\outputs\flutter-apk\app-debug.apk` using the local project Gradle distribution and JDK.

The standard Flutter command also succeeded:

```powershell
.\scripts\Flutter.ps1 build apk --debug --no-pub
```

The APK uses the Android emulator's backend addresses by default. For a physical phone, rebuild/run using `Run-App.ps1 -BackendHost YOUR_PC_LAN_IP` as described above. A debug APK is for development; release signing, public hosting and device testing remain outstanding.

The Gradle distribution and wrapper were checksum-verified and cached. `scripts/Flutter.ps1` uses a shorter project-local Java temporary directory to avoid Windows' Unix-domain socket path limit under the sandbox. No Windows Developer Mode or global Flutter preference changes were required.
