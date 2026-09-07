# Local setup

[Documentation index](README.md) · [Repository home](../README.md)

Run commands from the repository root unless a command explicitly changes directories.

## Setup

### 1. Clone

```bash
git clone https://github.com/JhiNResH/SAV-E.git
cd SAV-E
```

### 2. Bootstrap local secrets

```bash
cp -n SAV-E/Resources/Secrets.plist.template SAV-E/Resources/Secrets.plist
cp -n SAV-EShareExtension/Secrets.plist.template SAV-EShareExtension/Secrets.plist
```

Xcode also creates these local files from templates during build if they are missing. It does not overwrite existing `Secrets.plist` files; when templates change, compare manually and add new keys.

Fill local values in `SAV-E/Resources/Secrets.plist` and `SAV-EShareExtension/Secrets.plist`:

| Key | Purpose |
|---|---|
| `GOOGLE_PLACES_API_KEY` | Google Places lookup/details |
| `SAVE_API_URL` | Railway backend URL — for example, `https://wanderly-api-production.up.railway.app` |
| `SAVE_PLACE_SHARE_BASE_URL` | Place share route — for example, `https://sav-e-app.vercel.app/p` |
| `SAVE_TRIP_SHARE_BASE_URL` | Trip share route — for example, `https://sav-e-app.vercel.app/trip` |
| `SAVE_SHARE_BASE_URL` | Legacy trip fallback — for example, `https://sav-e-app.vercel.app/trip` |
| `SAVE_LIST_SHARE_BASE_URL` | Collaborative list route — for example, `https://sav-e-app.vercel.app/list` |
| `PRIVY_APP_ID` | Privy Dashboard → App Settings → Basics |
| `PRIVY_APP_CLIENT_ID` | Privy iOS client. Must allow bundle id `com.wanderly.app` and URL scheme `wanderly`. |

The app still reads legacy `WANDERLY_*` keys as a migration fallback for older local secrets, but new production config should use `SAVE_*` keys.

Keep real values out of commits.

### 3. Install backend dependencies

```bash
cd backend
npm install
npm run build
```

Railway service variables include:

```bash
DATABASE_URL=${{Postgres.DATABASE_URL}}
PRIVY_APP_ID=...
PRIVY_VERIFICATION_KEY='-----BEGIN PUBLIC KEY-----...'
PRIVY_APP_SECRET=...                 # needed for Privy user provisioning flows
SAVE_GUEST_SESSION_SECRET=...        # stable guest sessions across restarts
SAVE_MY_SAVES_SECRET=...             # stable /my/<token> links across restarts
GEMINI_API_KEY=...                   # backend-only AI parsing/analysis
SAVE_GEMINI_PROXY_MODELS=...         # comma-separated model allowlist for the proxy
GOOGLE_PLACES_API_KEY=...            # backend source recovery / place enrichment
```

`SAVE_GEMINI_PROXY_MODELS` defaults to `gemini-3.5-flash` alone. The app walks
`SAVEProductionConfig.defaultGeminiModelFallbacks`, so every model in that Swift
constant must appear here or the fallback leg answers 400.

`SAVE_GUEST_SESSION_SECRET` and `SAVE_MY_SAVES_SECRET` fall back to a random
per-process value, which invalidates guest sessions and `/my/` links on every
restart or deploy. Set both on Railway.

Mainland-China POI resolution through `POST /place-resolve` is optional. It needs
the explicit opt-in plus at least one key; otherwise the route answers 503 and the
app resolves China places through Apple Maps instead:

```bash
AMAP_USAGE_AUTHORIZED=true              # explicit opt-in; the route stays off otherwise
AMAP_INTERNATIONAL_WEB_SERVICE_KEY=...  # tried first, returns WGS84
AMAP_WEB_SERVICE_KEY=...                # 高德开放平台 domestic key, returns GCJ-02
```

Amap keys are backend-only. The iOS `Secrets.plist` templates must not carry
them; `SAVEProductionConfigTests` asserts that.

Apply/update the schema against Railway Postgres when migrations/schema change:

```bash
psql "$DATABASE_URL" -f backend/sql/schema.sql
```

### 4. Generate and open the Xcode project

```bash
xcodegen generate
open SAV-E.xcodeproj
```

Use the **SAV-E** scheme for the shipping app. The installed display name is **Savvy**; the internal app target remains `SAVE`, and bundle IDs stay under `com.wanderly.*` for production compatibility.
