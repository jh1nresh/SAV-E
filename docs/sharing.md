# Sharing and App Clip configuration

[Documentation index](README.md) · [Repository home](../README.md)

## Share, App Clip, and Universal Link routes

Savvy separates share actions from map actions:

- Share = Savvy link
- Maps = Apple Maps / Google Maps link

Production host: `sav-e-app.vercel.app`.

Current public route shapes:

```text
/p/{shortCode}
/p/{base64urlSharedPlaceDataJson}     # legacy readable
/trip/{base64urlSharedTripDataJson}
/list?d={base64SharedListPayloadJson}&r={viewer|editor}
/r/{code}
/u/{handle}?ref={code}
/my/{signedToken}
```

The full app handles installed-app Universal Links and new `savvy://` deep links while continuing to accept legacy `wanderly://` links. The App Clip target can preview Savvy place payloads and private/share cards. Full trip import, full list previews, and full referral previews are later surfaces unless a newer release explicitly changes that boundary.

For App Review:

- keep `applinks:sav-e-app.vercel.app` in the app entitlement
- keep `appclips:sav-e-app.vercel.app` in the App Clip entitlement
- keep `appclips:sav-e-app.vercel.app` and `com.apple.developer.associated-appclip-app-identifiers` in the main app entitlement
- set `APPLE_TEAM_ID` in Vercel so `npm run export:web` writes the real `/.well-known/apple-app-site-association`
- set `APPLE_APP_STORE_ID` and `APP_CLIP_BUNDLE_ID` for the Smart App Banner meta written by `save-rn/scripts/patch-web-bundle.js`
- disable bot challenges/WAF rules for `https://sav-e-app.vercel.app/p*`, `https://sav-e-app.vercel.app/r*`, and `https://sav-e-app.vercel.app/.well-known/apple-app-site-association`
- configure App Store Connect App Clip Experiences on `sav-e-app.vercel.app` only
- avoid `wanderly.app` until `https://wanderly.app/.well-known/apple-app-site-association` returns Apple association JSON without a challenge page

Without those Apple/domain steps, the same URL still opens the web app, but iOS will not invoke the App Clip.
