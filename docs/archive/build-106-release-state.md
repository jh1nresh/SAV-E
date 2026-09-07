# Build 106 release snapshot

[Documentation index](../README.md) · [Release guide](../releasing.md)

Historical snapshot, last verified on **2026-08-25**. This does not describe current App Store Connect or public-release status.

## Build 106 release state

Last verified on 2026-08-25:

- build 106 source is merged at `fc29cd4`, and [main CI run 32901152122](https://github.com/jh1nresh/SAV-E/actions/runs/32901152122) passed
- the signed app, Share Extension, and App Clip archive was uploaded successfully to App Store Connect
- the last App Store Connect read-back showed build 106 still processing
- build 106 visibility in the internal `Test g` group and a real-device smoke test are not yet verified
- external TestFlight, Beta Review, App Review, and public release are outside the current internal-testing boundary

An upload is not proof that the build is available to testers. Confirm Apple processing, the exact internal group, and a real-device launch separately before reporting the build as TestFlight-ready.
