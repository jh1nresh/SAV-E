# save-api

Supabase Edge Function that proxies SAV-E mobile persistence through a service-role backend.

Required secrets:

```bash
supabase secrets set SUPABASE_SERVICE_ROLE_KEY=...
supabase secrets set PRIVY_APP_ID=...
supabase secrets set PRIVY_VERIFICATION_KEY='-----BEGIN PUBLIC KEY-----...'
```

Deploy with Supabase JWT verification disabled so the function can receive and verify Privy access tokens:

```bash
supabase functions deploy save-api --no-verify-jwt
```

The mobile app sends:

```http
Authorization: Bearer <privy_access_token>
```

The function verifies the token and uses the verified `sub` claim as the owner id.
