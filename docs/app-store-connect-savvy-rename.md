# App Store Connect Savvy rename receipt

Read back on 2026-08-24 from App Store Connect app `6769216556`.

- Existing App Store record: preserved.
- Bundle ID: `com.wanderly.app` (preserved).
- Primary localization: English (U.S.); no additional App Information name localizations were configured.
- Pure `Savvy`: rejected by App Store Connect because the name is already in use.
- Saved App Store name: `Savvy: Save Places`.
- Installed binary display name: `Savvy`.
- Version state at read-back: `1.0`, Prepare for Submission.
- Latest TestFlight build visible at read-back: `1.0.0 (104)`.

The App Store Connect name save does not submit a version, select a build, upload a binary, change signing, or release the app. A future renamed build and refreshed screenshots must pass the normal review and release gates before users receive the binary rename.

Compatibility identities remain unchanged: bundle IDs, App Group, App Clip association, StoreKit product IDs, associated-domain hosts, and legacy `wanderly://` routes. New branded custom links use `savvy://`, while the app continues accepting the legacy scheme.
