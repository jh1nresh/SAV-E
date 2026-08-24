# Savvy — App Store Launch Checklist (1.0.0 / build 103)

Reviewed 2026-08-22. What's done in-repo vs. what only **you** can do (anything
needing your Apple ID, passwords, or App Store Connect — Claude can't sign in on
your behalf).

Legend: ✅ done · 🟡 ready, needs you · ⛔ blocker

Anything about archives, uploads, or App Store Connect state cannot be verified
from the repo. `build/` is untracked, so treat the Apple-side items below as
"confirm again" rather than as recorded state.

---

## 1. Build & signing
- ✅ Version `1.0.0`, build `103`, bundle `com.wanderly.app`, team `JC6858UYM9`.
- ✅ App icon present (`Assets.xcassets/AppIcon`).
- ✅ Release configuration compiles (CI builds an unsigned release candidate on every push to `main`).
- 🟡 **Xcode account** → Settings → Accounts must hold the Apple ID that owns team `JC6858UYM9`. This was the original upload blocker; re-confirm before archiving.

## 2. Archive & upload (you, in Xcode)
1. Xcode → select **Any iOS Device (arm64)** as the run destination.
2. Product → **Archive** (Release).
3. In the **Organizer**, select the archive → **Distribute App** → **App Store Connect** → **Upload**.
4. Wait for the build to finish **processing** in App Store Connect (a few min–1 hr).
   - If you re-archive, bump `CURRENT_PROJECT_VERSION` in `project.yml` (>103) and re-run `xcodegen generate` first. Editing only the generated `SAV-E.xcodeproj` is undone by the next generate.

## 3. App Store Connect — existing app record
- ✅ Keep the existing iOS record and bundle ID `com.wanderly.app`. English (U.S.) App Store name is **Savvy: Save Places** because the exact name **Savvy** is unavailable.

## 4. Listing metadata — paste from `app-store-listing.md`
- 🟡 Name, Subtitle, Promotional Text, Description, Keywords (en-US **and** zh-Hant).
- 🟡 Categories: Primary **Travel**, Secondary **Lifestyle**.
- 🟡 Verify `https://sav-e-app.vercel.app/support` and `/privacy` after the release web deploy.

## 5. Screenshots & icon
- ✅ v5 sets rendered from current app captures (#128): `specs/app-store-screenshots/v5/` (1242×2688), `v5-iphone-69/` (1260×2736), `v5-ipad-13/` (2048×2732), plus the raw simulator captures in `real-ui-v5/`. See `specs/app-store-screenshot-brief-v5.md`.
- 🟡 Upload each set to its matching ASC slot and check the contact sheets first.
- ✅ Trips stays out of the five screenshots while it is Beta, so nothing on the listing shows a feature the build does not ship.

## 6. App Privacy (you fill the ASC form)
- 🟡 Use the table in `app-store-listing.md`. Declare: account/email (Privy), saved content (Supabase), precise location (nearby search), search text. **Verify each against code — do not over-declare.**
- 🟡 Encryption: `ITSAppUsesNonExemptEncryption = false` is already set in Info.plist → answer "No" to export compliance.

## 7. App Review prep
- 🟡 **Demo account / sign-in:** review needs to get past auth. Provide either a working Apple/Google/email test login in the Review Notes, OR confirm the "Sample Place Clue" path lets a reviewer see the core loop without signing in.
- 🟡 **Review Notes:** one paragraph — "Savvy is a private place-memory app. Paste a link → it finds the place → confirm → it lands on a private map. No account purchase, no UGC feed." Mention location is used only for nearby search.
- 🟡 Age rating questionnaire → **4+**.

## 8. Pricing & release
- 🟡 Price: **Free**, all territories (or limit to your launch regions).
- ✅ The app is free. StoreKit code is present for a later Pro launch, but purchasing and enforcement remain disabled and the Pro entry is hidden in this build. No IAP is attached to v1.
- 🟡 Release: **Manually release** for v1 (so you control the moment), or phased automatic.

## 9. Submit
- 🟡 Attach processed build `103` → **Add for Review** → **Submit for Review**.

---

## Conversion polish already in place (why people will want to download)
- Single warm visual system across icon + screenshots + Memo logo (v5).
- Each screenshot sells **one outcome**, readable at thumbnail size.
- Copy leads with the real pain ("you lose the best places") and the private-by-default angle — a clear reason this isn't "another map app."

## Top things that block or hurt approval (do these)
1. **Xcode signing account** (step 1) — nothing ships until the team's Apple ID is present.
2. **Live Privacy + Support URLs** (step 4) — frequent auto-rejection.
3. **A way for review to see the app** past sign-in (step 7).
4. Make sure no screenshot shows a feature not in the build — the v5 set is captured from the real UI and leaves Trips Beta out.
