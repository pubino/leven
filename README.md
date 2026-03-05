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
