# Local verification

[Documentation index](README.md) · [Repository home](../README.md)

Run commands from the repository root unless a command explicitly changes directories.

## Local verification

### iOS compile (default)

Compile against the generic simulator destination without booting a runtime. Reuse the repository's canonical DerivedData directory:

```bash
scripts/xcodebuild-clean.sh \
  -project SAV-E.xcodeproj \
  -scheme SAV-E \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$HOME/Library/Developer/Xcode/DerivedData/SAVE-Codex" \
  CODE_SIGNING_ALLOWED=NO \
  COMPILER_INDEX_STORE_ENABLE=NO \
  build
```

### Runtime Swift/UI tests

Boot one headless simulator only when the changed behavior requires UIKit/SwiftUI runtime evidence, gestures, screenshots, accessibility, or an iOS XCTest bundle. Reuse one device and the same DerivedData directory, then shut the device down after the focused test.

```bash
scripts/xcodebuild-clean.sh \
  -project SAV-E.xcodeproj \
  -scheme SAV-E \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -derivedDataPath "$HOME/Library/Developer/Xcode/DerivedData/SAVE-Codex" \
  CODE_SIGNING_ALLOWED=NO \
  COMPILER_INDEX_STORE_ENABLE=NO \
  test
```

### Backend tests

```bash
cd backend
npm test
```

### Web fallback checks

```bash
cd save-rn
npm install
npm run check:import-links
npm run check:save-cards
npm run check:save-actions
npm run export:web
```

### Focused parser / fixture scripts

```bash
swift scripts/social_place_regression.swift
swift scripts/check-social-link-parser.swift
swift scripts/check-social-ocr-fixtures.swift
swift scripts/check-social-places-refine-fixtures.swift
```

The social place regression command reuses the canonical DerivedData path. It
uses the caller-owned `SAVE_TEST_SIMULATOR_UDID` when supplied; otherwise it
creates one temporary headless simulator, then shuts it down and deletes it
after the focused XCTest. It requires at least 10 GiB of free disk space.
