# SAV-E Passport Field Streak + Collection v0

Status: product spec. Founder 2026-09-04: approve DESIGN amendment for field streak;
streak = confirm / save Map Stamp / Visited only; redesign Passport sections 1–5.

## Required brief

- Paid job / failure: Passport did not give a simple return loop (login/return next step),
  consecutive memory-day signal, or collection progress framing.
- Acceptance: root Passport order is Hero → Field streak → Collection → Today on Savvy →
  Control pocket. Field streak counts only confirm / save Map Stamp / mark Visited days.
  Today includes a mark-visited return mission when an unvisited stamp exists, still capped
  at three live rows and hidden when empty. No XP, gems, login calendar, or grants.
- Failure fixture: empty account shows 0 streak, zero collection counts, and no empty quest card.
- Classification: feature
- Demand: founder request + approved DESIGN amendment
- Pricing: free core; streak/collection/missions never grant Pro
- Files: `DESIGN.md`, `SAV-E/Models/UserProfile.swift`, `SAV-E/Views/Profile/ProfileView.swift`,
  `SAV-E/ViewModels/MapViewModel.swift`, `SAV-E/App/ContentView.swift`, Passport Today tests/script
- Verification: `python3 scripts/check-passport-today-on-savvy.py`; focused Passport catalog/streak tests
- Security/privacy: streak days stay on-device in UserDefaults; no new network or entitlement path
- Human approval: DESIGN amendment (approved); merge; no TestFlight/store publish from this ticket

## Forbidden

- Login check-in that awards streak without memory actions
- XP / Level / gems / Path / Shop / Progress chrome
- Entitlement grants from completing missions
