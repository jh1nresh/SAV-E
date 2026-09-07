# Release and TestFlight

[Documentation index](README.md) · [Repository home](../README.md)

These are release instructions, not evidence of a current release. Signing, upload, and distribution require explicit approval under [AGENTS.md](../AGENTS.md). Run commands from the repository root.

## TestFlight archive

Set `APPLE_TEAM_ID` to the 10-character Apple Developer Team ID for the account that owns the App IDs. XcodeGen passes it into all iOS targets as `DEVELOPMENT_TEAM`.

```bash
export APPLE_TEAM_ID=ABCDE12345
xcodegen generate
xcodebuild \
  -project SAV-E.xcodeproj \
  -scheme SAV-E \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$PWD/build/SAV-E.xcarchive" \
  -allowProvisioningUpdates \
  APPLE_TEAM_ID="$APPLE_TEAM_ID" \
  archive
```

Prepare App Store Connect upload options. The generated options are external-TestFlight ready by default. Set `TESTFLIGHT_SCOPE=internal` only for internal-only review builds.

```bash
APPLE_TEAM_ID="$APPLE_TEAM_ID" scripts/prepare-testflight-export-options.sh
TESTFLIGHT_SCOPE=internal APPLE_TEAM_ID="$APPLE_TEAM_ID" scripts/prepare-testflight-export-options.sh build/ExportOptions.TestFlight.Internal.plist
```

Upload:

```bash
xcodebuild \
  -exportArchive \
  -archivePath "$PWD/build/SAV-E.xcarchive" \
  -exportPath "$PWD/build/TestFlightUpload" \
  -exportOptionsPlist "$PWD/build/ExportOptions.TestFlight.plist" \
  -allowProvisioningUpdates \
  APPLE_TEAM_ID="$APPLE_TEAM_ID"
```

## First TestFlight boundary

Ship the native iOS app, Share Extension, and embedded App Clip for Savvy share links.

Before upload:

- register App IDs for `com.wanderly.app`, `com.wanderly.app.ShareExtension`, and `com.wanderly.app.Clip`
- enable App Group `group.com.wanderly.app` for app and Share Extension
- configure signing team/profiles in Xcode or release xcconfig
- confirm App Store icon and privacy manifest are included
- keep real API keys out of commits and restrict bundled keys where provider dashboards allow it

These Apple identifiers are the existing production compatibility layer. User-facing naming, target display names, release config keys, and share URLs should use Savvy / SAVE naming.
