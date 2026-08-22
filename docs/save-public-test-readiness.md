# SAV-E Public Test Readiness

Generated: 2026-06-23 · Reviewed: 2026-08-22 (build 103)

This checklist tracks the seven readiness gaps that must stay separate from
"the app builds locally." Local code can prove client behavior; Apple,
production secrets, and device install state require live credentials/device
proof.

## 1. TestFlight and device smoke proof

Current in-repo proof:

- Bundle `com.wanderly.app`, version `1.0.0`, build `103`, team `JC6858UYM9`,
  App Store id `6769216556`. Build numbers come from `project.yml`.
- `Tests/SAVEUITests/SAVEUISmokeHarnessTests.swift` covers the five required
  smoke paths: auth, location, nearby restaurants/cafes, share IG/Maps link,
  review candidate confirm/save.

Archives and export logs live under the untracked `build/` directory, so no
upload receipt can be read from this repo. The earlier build-78 archive and its
`Upload succeeded` export log were local-only evidence.

Still required before public TestFlight:

- Confirm the current build is visible and processed in App Store Connect.
- Run the five-path smoke harness on a real iPhone with the TestFlight build,
  not only simulator/local debug.
- Save a screenshot or text receipt with device, build number, and pass/fail.

Blocked locally when these are missing:

- `APP_STORE_CONNECT_API_KEY_PATH`
- `APP_STORE_CONNECT_API_KEY_ID`
- `APP_STORE_CONNECT_ISSUER_ID`

## 2. App Clip and shared links

Required proof:

- `https://sav-e-app.vercel.app/.well-known/apple-app-site-association` serves
  `applinks` and `appclips`.
- `/p/*` pages keep web preview behavior.
- `/p/*` HTML includes an Apple Smart App Banner with the configured App Clip
  bundle id.
- App Store Connect has an App Clip Experience for
  `https://sav-e-app.vercel.app/p/*`.
- iPhone checks:
  - app installed: link opens full SAV-E app.
  - app not installed: link surfaces App Clip or install CTA.

Do not touch Privy auth/session config for this checklist.

## 3. Social link recovery long tail

Current high-risk cases:

- Instagram captions where the venue appears only as a handle inside a quoted
  creator title.
- Instagram posts with multiple venues in one caption.
- URL-only or preview-only iMessage links.
- China/Taiwan food links where OCR contains the address but provider matching
  is missing coordinates.

Required regression behavior:

- Keep creator/source handles separate from venue handles.
- Bind venue handles to the nearest address or pin evidence.
- Return multiple candidates when a post clearly names multiple venues.
- Preserve source-only clues when coordinates are not proven.

## 4. Runtime config risk

Production checks:

- `GEMINI_API_KEY` exists where backend AI analysis runs. Without it
  `/v0/llm/gemini-generate-content` answers 503, which takes down every
  backend-proxied AI feature at once — link analysis, review analysis, the ask
  drawer, `maatPublicWebAnalysis`, and Sendblue venue extraction.
- `SAVE_GEMINI_PROXY_MODELS` lists every model the app may fall back to. It
  defaults to `gemini-3.5-flash` alone, while the client walks
  `SAVEProductionConfig.defaultGeminiModelFallbacks`, so an unlisted fallback
  answers 400 `Unsupported Gemini model` and the app has no working second
  choice exactly when the first model is failing. Keep this variable and that
  Swift constant in step.
- Google Places key exists where place details are fetched.
- `SAVE_GUEST_SESSION_SECRET` is set. It falls back to a random per-process
  value, which would drop guest sessions on every restart or deploy.
- `SAVE_MY_SAVES_SECRET` is deliberately allowed to stay unset: it falls back to
  the guest-session secret, so `/my/` links are already stable. Introducing a
  separate value invalidates every existing `/my/` link and feeds
  `previousAccountRefSecrets`, so only set it as a considered rotation.
- Amap is intentionally on or off: `POST /place-resolve` needs
  `AMAP_USAGE_AUTHORIZED=true` plus a domestic or international key, and answers
  503 otherwise. China places then resolve through Apple Maps.
- `ai_usage_events` from `backend/sql/schema.sql` is applied. Without the table
  the usage route reports `warming_up` and records nothing; it never blocks a
  request, so a missing table is invisible to users and to you.
- Public web enrichment flag is intentionally enabled or intentionally disabled.
- Privy configuration works for full app and iMessage-created identities.
- Failed AI/place details requests expose a specific status, not only generic
  "AI request failed."

## 5. Nearby/list sorting

Client behavior:

- Saved/review candidates must not outrank truly nearby options just because
  they were saved in another country.
- "Nearest" sort must use current device location when available.
- Without location permission, the app may keep the existing stable order, but
  it must not claim distance-based ranking.

In-repo coverage:

- The `testPlaceListNearestSortUsesCurrentLocation` case named here in June no
  longer exists. The closest current coverage is
  `SaveSearchControllerTests.testUnsavedMapCandidatesSortByDistanceWhenScoresTie`,
  which only pins the tie-break. A regression test for nearest-sort against the
  current device location is still missing — see section 7.

## 6. Trip and itinerary planning

Trip planner V2 landed in #116: save-as-trip, Routes API waypoint
optimization, travel legs, and opening-hours annotation. See
`specs/deterministic-trip-planner-v2.md`.

Client behavior:

- Do not fake Google Directions/Gemini optimization anywhere in the trip UI.
- Normalize stored timelines deterministically.
- Use the drawer/detail itinerary planner for coordinate-aware route drafts and
  LLM polish, and fall back to the unoptimized order when the route service
  fails rather than inventing one.

In-repo coverage:

- `Tests/SocialPlacePipelineTests/TripRouteServiceTests.swift`, including
  `testRouteEnhancedPlanFallsBackWhenServiceThrows` and
  `testRouteEnhancedPlanIgnoresServiceThatDropsPlaces`.

## 7. Backlog and QA ownership

Track as a single public-test gate until all boxes are green:

- Device smoke proof for the current TestFlight build.
- App Clip/shared-link iPhone proof.
- Production Gemini/Google Places/Privy config proof, plus the stable session
  secrets and the applied `ai_usage_events` table from section 4.
- Social parser golden fixtures for multi-place and handle-only venues.
- Nearby recommendation/list sort regression.
- Itinerary polish path proof from detail page to LLM-polished route.
- Backend deploy receipt after any backend config/code changes.
