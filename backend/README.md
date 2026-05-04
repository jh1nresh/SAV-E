# Wanderly Railway Backend

Railway-hosted API for Wanderly mobile persistence. It replaces the previous Supabase Edge Function while preserving the iOS API contract.

## Environment

```bash
DATABASE_URL=postgresql://...
PRIVY_APP_ID=...
PRIVY_VERIFICATION_KEY='-----BEGIN PUBLIC KEY-----...'
PORT=3000
```

Railway provides `DATABASE_URL` and `PORT`. Set the Privy values on the backend service.

## Local

```bash
npm install
npm run build
npm run start
```

Apply schema:

```bash
psql "$DATABASE_URL" -f backend/sql/schema.sql
```

## Routes

Persistence routes accept either `Authorization: Bearer <Privy access token>` or `x-wanderly-guest-id: guest_<uuid>`.

- `GET /places`
- `POST /places`
- `PATCH /places/:id`
- `DELETE /places/:id`
- `GET /trips`
- `POST /trips`
- `PATCH /trips/:id`
- `DELETE /trips/:id`
- `GET /profile`
- `PATCH /profile`
