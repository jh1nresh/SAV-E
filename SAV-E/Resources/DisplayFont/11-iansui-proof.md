# Iansui proof

- Bundled Clip file: `SAV-E/Resources/DisplayFont/Iansui-ClipTitles.ttf`
- SAVEClip resource: `Iansui-ClipTitles.ttf in SAVEClip Resources`
- UIFont / PostScript name: `Iansui-Regular` (`ClipDisplayType.cjkName`)
- Register: `CTFontManagerRegisterFontsForURL` of `Iansui-ClipTitles.ttf`
  in `ClipDisplayType.register`
- Used for: place name, list title, and state titles when locale is zh-Hant
  (`ClipDisplayType.title`)
- Latin shop-name fallback: Iansui cascades to Caveat via
  `UIFontDescriptor.AttributeName.cascadeList`, then the system font
- Not shipped in the Clip: `Iansui-SavvySubset.ttf` (3.48 MB)
