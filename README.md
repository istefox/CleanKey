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
3. Click **Start Lock** — the screen goes dark and input is blocked
4. Clean your keyboard and trackpad
5. The lock lifts automatically when the timer expires
6. **Need out early?** Press Escape three times quickly (within 1.5 s)

## Build from source

```bash
git clone https://github.com/stefer/CleanKey.git
cd CleanKey
xcodebuild build -scheme CleanKey -destination 'platform=macOS'
```

Run tests:

```bash
xcodebuild test -scheme CleanKey -destination 'platform=macOS'
```

Requires Xcode 16+ and macOS 14 SDK.

## License

MIT — see [LICENSE](LICENSE).
