# Leven

A macOS app that captures audio from any running application using ScreenCaptureKit.

Select a running app, hit Record, and Leven captures its audio output to an M4A file — no virtual audio devices or kernel extensions needed.

## Requirements

- macOS 14.0+
- Xcode 16.0+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (to generate the Xcode project)

## Building

```bash
xcodegen generate
xcodebuild -project Leven.xcodeproj -scheme Leven -configuration Debug build
```

Or open `Leven.xcodeproj` in Xcode after generating.

## Usage

1. Launch Leven — it will prompt for Screen & System Audio Recording permission on first run.
2. Select a running application from the dropdown.
3. Press **Record** (Cmd+R) to start capturing audio.
4. Press **Stop** (Cmd+R again) when finished.
5. Press **Save** (Cmd+S) to export the recording as an M4A file.

### Settings (Cmd+,)

- View current screen recording permission status.
- Reset the TCC permission (requires app restart for macOS to re-prompt).
- Open System Settings to the Screen Recording privacy pane.

## Releasing

Requires a Developer ID certificate and an app-specific password stored via:

```bash
xcrun notarytool store-credentials notary --apple-id YOUR_APPLE_ID --team-id YOUR_TEAM_ID
```

Then to cut a release:

```bash
VERSION=X.Y.Z

# 1. Tag and push
git tag -s v$VERSION -m "v$VERSION"
git push origin v$VERSION

# 2. Build a signed release archive
xcodegen generate
xcodebuild -project Leven.xcodeproj -scheme Leven -configuration Release \
  -archivePath /tmp/Leven.xcarchive archive \
  CODE_SIGN_IDENTITY="Developer ID Application" CODE_SIGN_STYLE=Manual

# 3. Create a DMG
rm -rf /tmp/Leven-dmg-staging && mkdir /tmp/Leven-dmg-staging
cp -R /tmp/Leven.xcarchive/Products/Applications/Leven.app /tmp/Leven-dmg-staging/
ln -s /Applications /tmp/Leven-dmg-staging/Applications
hdiutil create -volname Leven -srcfolder /tmp/Leven-dmg-staging -ov -format UDZO \
  /tmp/Leven-v$VERSION.dmg

# 4. Notarize and staple
xcrun notarytool submit /tmp/Leven-v$VERSION.dmg --keychain-profile notary --wait
xcrun stapler staple /tmp/Leven-v$VERSION.dmg

# 5. Create GitHub release and upload
gh release create v$VERSION --title "v$VERSION" --notes "Release notes here."
gh release upload v$VERSION /tmp/Leven-v$VERSION.dmg
```

## License

[MIT](LICENSE.md)
