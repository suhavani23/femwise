# Restore ingredient analysis on the existing Render service

The scanner is now part of `backend/account_api.py`. Use the existing
`https://femwise.onrender.com` service; no extra server is needed.

Render settings:

- Root directory: `backend`
- Build command: `pip install -r requirements.txt`
- Start command: `uvicorn account_api:app --host 0.0.0.0 --port $PORT`
- Keep your existing `MONGODB_URI`, database name and `OPENAI_API_KEY` values.
- `OPENAI_MODEL` is optional and defaults to `gpt-4o-mini`.

After the updated code reaches the connected GitHub branch, let Render deploy
it automatically or select **Manual Deploy → Deploy latest commit**.
If your build command already uses `requirements-accounts.txt`, it also works:
that file now includes the OpenAI SDK.

Open `https://femwise.onrender.com/food/status` after deployment. It should return
`ingredient_scanner: true`, `analysis_configured: true`, and `version: 1`.
Configuration status only confirms a key is present. A successful ingredient
request is needed to confirm the key's billing and model access.

The route is `POST /extract_ingredients` with JSON `{"text":"Ingredients: oats"}`.
The app obtains an anonymous session automatically through `/auth/guest`; there
is no login screen. The route validates input, shares the MongoDB-backed request
limit, handles provider errors and returns a structured AI label review.
The API uses OpenAI Structured Outputs, following the
[official OpenAI documentation](https://developers.openai.com/api/docs/guides/structured-outputs).

The scanner sends ingredient text to the backend and OpenAI. It does not send
tracking records or retain ingredient text/analysis in MongoDB. It does not
claim results are verified against the old ingredient knowledge graph. The
legacy Neo4j/Ollama/Chroma services are not required for this route. Cooked-food
analysis remains unavailable and its button stays hidden.

APK: `build/app/outputs/flutter-apk/FemWise-scanner-demo-v1.0.2.apk`.
Scanner: bottom food icon → **Scan Ingredients** → camera, gallery or typed input.

Five sample irregular cycles span about five months. Fresh installations show
demo history. On an existing installation, use the top-right menu → **Show demo
history**. Choose **Use my own records** to return to your real encrypted data.
The datasets use separate storage keys; enabling demo history does not overwrite
real records. Demo history is marked as sample data and stays on the phone.

Validation: 14 Flutter tests passed; 24 backend tests passed and 1 real-MongoDB
integration test was skipped. The provider request/structured parser was tested
with mocked HTTP responses. Device camera, OCR and playback need a physical
phone check; no device was connected. This APK is debug-signed, for testing.
