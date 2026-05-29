# CleanKey

![MIT License](https://img.shields.io/badge/license-MIT-blue.svg)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-brightgreen.svg)

A macOS menu-bar utility that locks keyboard and trackpad input for a fixed duration so you can safely clean your hardware — then restores everything automatically, no password needed.

## Features

- Locks all keyboard and trackpad input system-wide via macOS Accessibility API
- Fullscreen dark overlay covers every connected display with a live countdown
- Duration picker: 30 seconds to 10 minutes via a slider in the menu bar
- **Emergency unlock:** hold Escape 3 times within 1.5 seconds to exit early
- Remembers your last-used duration between sessions
- Menu bar only — no Dock icon, no clutter

## Requirements

- macOS 14 Sonoma or later
- Apple Silicon or Intel Mac

## Install

Download the latest DMG from [Releases](../../releases), open it, drag CleanKey to Applications.

**On first launch**, macOS will ask you to grant Accessibility access:

1. Open **System Settings → Privacy & Security → Accessibility**
2. Enable **CleanKey**
3. Return to the app — the menu bar icon appears immediately

## Usage

1. Click the CleanKey icon in the menu bar
2. Drag the slider to set your cleaning duration
3. Click **Start** — the screen goes dark and input is blocked
4. Clean your keyboard and trackpad
5. The lock lifts automatically when the timer expires
6. **Need out early?** Press Escape three times quickly (within 1.5 s)

## Build from source

Requires Xcode 16+, macOS 14 SDK, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
git clone https://github.com/stefer/CleanKey.git
cd CleanKey
xcodegen generate
xcodebuild build -scheme CleanKey -destination 'platform=macOS'
```

Run tests:

```bash
xcodebuild test -scheme CleanKey -destination 'platform=macOS'
```

Verify code signature after build:

```bash
codesign --verify --deep --strict CleanKey.app
spctl --assess --verbose CleanKey.app
```

## Troubleshooting

**Menu bar icon does not appear after launch.**
CleanKey requires Accessibility permission before it shows the icon. Open
System Settings → Privacy & Security → Accessibility and ensure CleanKey is
toggled on. The icon appears immediately after the permission is granted
without requiring a restart.

**Keyboard or trackpad is not blocked during a lock.**
Accessibility permission may have been revoked since launch. CleanKey posts a
notification and restores input within ~5 seconds if it detects this. Re-grant
permission in System Settings, then start a new lock.

**Overlay does not appear but input is blocked.**
This should not occur in normal operation. If it does, triple-press Escape
quickly (within 1.5 s) to trigger the emergency unlock, then re-launch the app.

**Lock does not release after the timer expires.**
Press Escape three times quickly (within 1.5 s) to force an emergency unlock.
The triple-Escape combo is always available while the tap is active.

## License

MIT — see [LICENSE](LICENSE).
