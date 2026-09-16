# EchoNote

Android recording-notes client (Flutter) and a small Node.js API.

This commit bootstraps the repo: an empty Flutter shell, compile-time API
base URL, and a health endpoint. Recording and transcription land in later
commits.

## Layout

```text
lib/                 Flutter client
server/src/          Express API
```

The Flutter UI must not call SQLite, files, or HTTP directly once those
layers exist. API keys stay in `server/.env` and are never baked into the APK.

## Backend

```bash
cd server
copy .env.example .env
npm install
npm start
npm test
```

`GET /health` on port `3000` (override with `PORT`) should return:

```json
{"ok":true,"service":"echonote-server"}
```

The process binds `0.0.0.0` so a phone on the same LAN can reach it.

### Environment

| Name | Purpose |
| --- | --- |
| `PORT` | Listen port |
| `ASR_PROVIDER` | Speech-to-text vendor; unused until transcription is added |
| `LLM_PROVIDER` | Summary vendor; unused until summarization is added |

## Client

```bash
flutter pub get
flutter test
flutter run --dart-define=API_BASE_URL=http://192.168.x.x:3000
```

`10.0.2.2` is the Android emulator alias for the host. A physical device
must use the machine LAN IP or an HTTPS deployment. Debug builds allow
cleartext HTTP; release builds should use HTTPS.

## License keys and signing

Do not commit `server/.env`, `android/key.properties`, or keystore files.
