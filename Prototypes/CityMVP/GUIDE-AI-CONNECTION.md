# Guide AI connection — local candidate only

The prototype defaults to disconnected. Its normal project generation does not
read production API defaults, local secrets or any implicit endpoint config.
The app can prepare and review a selected-data request while disconnected; Send
stays disabled. This is not a live-model verification result.

To prepare an approved test connection, copy `guide-ai.example.json` to a local
file outside Git, set the named test backend root and explicitly enable requests:

```sh
python3 Prototypes/CityMVP/generate-project.py --guide-config /absolute/path/guide-ai.local.json
```

The config accepts only `allowRequests` and `apiBaseURL`. Do not put credentials
in this file. HTTPS roots or localhost HTTP roots are accepted; credentials,
query strings, fragments and path prefixes are rejected. Regenerating without
the argument restores the disconnected target. This modifies only the generated
City Lab project, never the production project.

A real request also requires the existing authenticated session to work with
that exact test backend. There is no guest bootstrap, raw key fallback, automatic
retry, model fallback or repair request. Analysis start/finish and the existing
Gemini proxy participate in the current allowance path. The backend permits one
text part, input up to 16 KiB and output up to 1,024 tokens; preflight enforces
these limits before starting analysis. Cancellation cannot recall data already
sent and does not promise a quota refund.

The review shows the question and explicitly selected venue names/categories,
plus only source IDs separately chosen by the user. No saved address, coordinate,
note, rating, photo, visit history or unselected save/source is attached. Text
typed into the question is itself part of the reviewed request. Copied labels
and reasons remain unsigned and unverified.

The model may return at most two selected venue IDs with their own selected
source IDs. No generated factual prose is displayed. The UI quotes the original
source text, marks its identity uncertainty and opens only the current saved
place. Suggestions do not save a place or authenticate a recommendation.
Edited selection, changed source/catalog, cancellation or account change
invalidates pending results. Account changes also clear and close request review.

Live verification is still a separate gate: it needs a specified approved test
endpoint/account and explicit authority for analysis usage writes and a bounded
provider call. Local URLProtocol tests intercept all requests and must not be
described as a real AI conversation. No production guest session or provider
request has been created by this work.

Generation fields and completion status follow the primary
[Gemini generateContent reference](https://ai.google.dev/api/generate-content?hl=en).
Structured JSON output does not establish factual truth; strict local ID checks
and original-source rendering enforce the narrower contract here.
