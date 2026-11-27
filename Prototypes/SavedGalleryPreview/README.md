# Saved gallery local preview

Swift adaptation of https://appllama.io/r/c3s8ck, using Savvy's canonical pink/purple tokens and real, branch-specific photographs. The local Debug collection keeps search, region/category filters, pending review and place detail actions. Lighting and torch reveals are ephemeral presentation state; they never save, share or mark a visit.

The standalone native host uses the **same** `SavedGalleryWall.swift` as the Debug app collection. Its nine licensed public photographs are explicit preview fixtures, not account data. Each photo retains its source and credit. The tenth fixture exercises the no-photo state. App cards use the existing photo loader/provider policy, with a conservative bundled-photo fallback: exact OSM identity plus nearby WGS84 coordinates, or exact normalized name plus street address plus coordinates. Ambiguous branches stay without a photo.

## Local build

Requires Xcode and XcodeGen. Choose one task-owned output directory and an exclusive build lease; follow the repository's disk and simulator rules.

```sh
python3 Prototypes/SavedGalleryPreview/prepare.py --output "$GALLERY_OUTPUT/Project"
xcodegen generate --spec "$GALLERY_OUTPUT/Project/project.json"
xcodebuild -project "$GALLERY_OUTPUT/Project/SavvySavedGallery.xcodeproj" \
  -scheme SavvySavedGallery -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$GALLERY_OUTPUT/DerivedData" \
  CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=NO build
python3 -B -m unittest discover -s Tests/ci -p 'test_gallery_photo_catalog.py' -v
```

`prepare.py` extracts `SaveBrandUI` from `Color+Theme.swift`; it does not maintain a second palette. Generated project, cache and screenshots belong outside source control.

## Runtime evidence and remaining review

The 2026-11-27 local run passed all three `GalleryUITests` on an iPhone 17 simulator (iOS 27.2), including cord pull, torch reveal, photo detail, search and accessibility-sized text. Light, night, torch and large-text screenshots were inspected. The full Savvy generic simulator build and 18 focused native source/photo tests also passed. Independent review, required CI and real-account/device verification remain pending.

For subsequent runtime checks, use one owned iOS simulator and capture the real light/night screens. Manually compare the source video against cord anchoring and release, frame proportions, scroll edges, moving torch mask, card opening/dismissal, larger text and Reduce Motion. Verify the Debug integration with real account-scoped Saved data separately from this fixture host.

A generic build is not simulator interaction proof or full Savvy build proof. Run the interaction suite and visually inspect the captured screens before marking this candidate ready. Do not substitute generated mockups for runtime screenshots.

This candidate is not a pixel-identical reproduction: source illustrations/characters are replaced with real place photos and a native accessible torch control; Savvy navigation and typography are retained. It does not alter the shipping Ink root, deploy to a phone or authorize a release.
