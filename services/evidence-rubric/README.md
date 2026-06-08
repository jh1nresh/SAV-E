# SAV-E Evidence Rubric Service

Small Railway service used by `wanderly-api` as `SAVE_EVIDENCE_RUBRIC_URL`.

## Environment

```bash
SAVE_EVIDENCE_RUBRIC_TOKEN=shared_backend_bearer_token
GEMINI_API_KEY=...
GEMINI_MODEL=gemini-3.5-flash
PORT=3000
```

## Routes

- `GET /health` returns readiness booleans without exposing secrets.
- `POST /rubric` requires `Authorization: Bearer <SAVE_EVIDENCE_RUBRIC_TOKEN>` and returns:

```json
{
  "evidence_tier": "likely",
  "confidence_reason": "Source and media evidence cite the same venue and address.",
  "missing_info": ["Verified coordinates", "User confirmation before saving as Map Stamp"]
}
```

The service only evaluates the safe projection sent by `wanderly-api`. It must not invent addresses, coordinates, or place IDs.
