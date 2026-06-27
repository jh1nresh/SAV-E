# SAV-E — App Store Launch Checklist (1.0.0 / build 81)

What's done in-repo vs. what only **you** can do (anything needing your Apple ID,
passwords, or App Store Connect — Claude can't sign in on your behalf).

Legend: ✅ done · 🟡 ready, needs you · ⛔ blocker

---

## 1. Build & signing
- ✅ Version `1.0.0`, build `80`, bundle `com.wanderly.app`, team `JC6858UYM9`.
- ✅ App icon present (`Assets.xcassets/AppIcon`).
- ✅ Release configuration compiles (verified via `xcodebuild ... -configuration Release`).
- ⛔ **Sign into Xcode** → Settings → Accounts → add the Apple ID that owns team `JC6858UYM9`. *(Organizer currently shows "No Accounts" — this is the upload blocker. Only you can do this.)*

## 2. Archive & upload (you, in Xcode)
1. Xcode → select **Any iOS Device (arm64)** as the run destination.
2. Product → **Archive** (Release).
3. In the **Organizer**, select the archive → **Distribute App** → **App Store Connect** → **Upload**.
4. Wait for the build to finish **processing** in App Store Connect (a few min–1 hr).
   - If you re-archive, bump `CURRENT_PROJECT_VERSION` in `project.yml` (>79) and re-run `xcodegen generate` first.

## 3. App Store Connect — create the app record (you)
- 🟡 apps → **+** → New App → Platform iOS, Name **SAV-E**, Primary language English (U.S.), Bundle ID `com.wanderly.app`, SKU `save-1`.

## 4. Listing metadata — paste from `app-store-listing.md`
- 🟡 Name, Subtitle, Promotional Text, Description, Keywords (en-US **and** zh-Hant).
- 🟡 Categories: Primary **Travel**, Secondary **Lifestyle**.
- 🟡 Support URL + Privacy Policy URL — **must be live pages before submit** (placeholders in listing doc). This is a common rejection cause if missing.

## 5. Screenshots & icon
- ✅ Rendered set in `specs/app-store-screenshots/v2/` (1242×2688).
- 🟡 Upload the 5 PNGs to the 6.5" slot; provide a 6.9" set too (re-export at 1290×2796 if ASC requires — the board scales).
- 🟠 **Recommended before submit:** swap the in-phone mockups for real build-79 simulator captures (Apple prefers screenshots that match the live app; see `v2/NOTES.md`). Marketing frames are allowed, but real UI lowers 2.3.x review risk.

## 6. App Privacy (you fill the ASC form)
- 🟡 Use the table in `app-store-listing.md`. Declare: account/email (Privy), saved content (Supabase), precise location (nearby search), search text. **Verify each against code — do not over-declare.**
- 🟡 Encryption: `ITSAppUsesNonExemptEncryption = false` is already set in Info.plist → answer "No" to export compliance.

## 7. App Review prep
- 🟡 **Demo account / sign-in:** review needs to get past auth. Provide either a working Apple/Google/email test login in the Review Notes, OR confirm the "Sample Place Clue" path lets a reviewer see the core loop without signing in.
- 🟡 **Review Notes:** one paragraph — "SAV-E is a private place-memory app. Paste a link → it finds the place → confirm → it lands on a private map. No account purchase, no UGC feed." Mention location is used only for nearby search.
- 🟡 Age rating questionnaire → **4+**.

## 8. Pricing & release
- 🟡 Price: **Free**, all territories (or limit to your launch regions).
- 🟡 Release: **Manually release** for v1 (so you control the moment), or phased automatic.

## 9. Submit
- 🟡 Attach build 79 → **Add for Review** → **Submit**.

---

## Conversion polish already in place (why people will want to download)
- Single warm visual system across icon + screenshots + Memo logo (v2).
- Each screenshot sells **one outcome**, readable at thumbnail size.
- Copy leads with the real pain ("you lose the best places") and the private-by-default angle — a clear reason this isn't "another map app."

## Top things that block or hurt approval (do these)
1. **Sign into Xcode** (step 1) — nothing ships until this.
2. **Live Privacy + Support URLs** (step 4) — frequent auto-rejection.
3. **A way for review to see the app** past sign-in (step 7).
4. Make sure no screenshot shows a feature not in the build (proof/coming-soon was already removed from the app this session).
