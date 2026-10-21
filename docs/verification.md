# Local verification

[Documentation index](README.md) · [Repository home](../README.md)

Run commands from the repository root unless a command explicitly changes directories.

## Local verification

Before iOS checks, export `SAVE_DERIVED_DATA_PATH` as an absolute directory owned
by this task. Use a unique path for concurrent tasks. Reuse an existing cache only
with exclusive ownership enforced by a lock or a single serialized build owner.
Check free disk space first; below 10 GiB, stop new Xcode/runtime work unless
cleanup or that task's storage risk has been explicitly authorized.

The exported variable configures both the commands below and
`scripts/run-social-place-regression.sh`. That helper has a legacy shared-cache
fallback when the variable is unset; set it explicitly before running the helper.

### iOS compile (default)

Compile against the generic simulator destination without booting a runtime:

```bash
scripts/xcodebuild-clean.sh \
  -project SAV-E.xcodeproj \
  -scheme SAV-E \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "${SAVE_DERIVED_DATA_PATH:?Export a task-owned DerivedData path}" \
  CODE_SIGNING_ALLOWED=NO \
  COMPILER_INDEX_STORE_ENABLE=NO \
  build
```

### Runtime Swift/UI tests

Boot one headless simulator only when the changed behavior requires UIKit/SwiftUI runtime evidence, gestures, screenshots, accessibility, or an iOS XCTest bundle. Reuse one device and the same DerivedData directory, then shut the device down after the focused test.

Before runtime checks, reserve one simulator exclusively using a device lock or
a single serialized owner, and export its UDID as `SAVE_TEST_SIMULATOR_UDID`.
A UDID identifies the device but does not itself establish ownership; do not
borrow a device currently owned by another task. The regression helper also
honors this exported UDID and does not delete the caller-owned device.

```bash
scripts/xcodebuild-clean.sh \
  -project SAV-E.xcodeproj \
  -scheme SAV-E \
  -destination "platform=iOS Simulator,id=${SAVE_TEST_SIMULATOR_UDID:?Export an exclusively owned simulator UDID}" \
  -derivedDataPath "${SAVE_DERIVED_DATA_PATH:?Export a task-owned DerivedData path}" \
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
: "${SAVE_DERIVED_DATA_PATH:?Export a task-owned DerivedData path}"
swift scripts/social_place_regression.swift
swift scripts/check-social-link-parser.swift
swift scripts/check-social-ocr-fixtures.swift
swift scripts/check-social-places-refine-fixtures.swift
```

The social place regression command reuses the exported task-owned DerivedData path. It
uses the caller-owned `SAVE_TEST_SIMULATOR_UDID` when supplied; otherwise it
creates one temporary headless simulator, then shuts it down and deletes it
after the focused XCTest. It requires at least 10 GiB of free disk space.
