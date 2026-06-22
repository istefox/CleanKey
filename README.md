# CleanKey

![MIT License](https://img.shields.io/badge/license-MIT-blue.svg)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-brightgreen.svg)

A macOS menu-bar utility that locks keyboard and trackpad input for a fixed duration so you can safely clean your hardware — then restores everything automatically, no password needed.

## Features

- Locks keyboard and trackpad input system-wide via the macOS Accessibility API
- Fullscreen dark overlay covers every connected display with a live countdown
- Quick-pick menu for instant locks at preset or last-used durations
- **Global hotkey** — record a shortcut in Settings to start a lock from any app
- **Keep Awake** — prevent display sleep independently of the lock timer
- Sound feedback on lock start and unlock
- **Emergency unlock:** press Escape 3 times quickly (within 1.5 s) to exit early
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

Requires Xcode 16+ and macOS 14 SDK.

```bash
git clone https://github.com/istefox/CleanKey.git
cd CleanKey
xcodebuild build -scheme CleanKey -destination 'platform=macOS'
```

Run tests:

```bash
xcodebuild test -scheme CleanKey -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO
```

Build a signed DMG locally (requires Developer ID certificate in Keychain):

```bash
bash scripts/build-dmg.sh
# Output: dist/CleanKey-<version>.dmg
```

Verify code signature after build:

```bash
codesign --verify --deep --strict CleanKey.app
spctl --assess --verbose CleanKey.app
```

## GitHub Actions releases

Pushing a version tag triggers the release workflow, which builds a signed and notarized DMG and uploads it to a GitHub Release automatically:

```bash
git tag v1.2.0
git push origin v1.2.0
```

Configure these repository secrets before using the workflow:

| Secret | Description |
|---|---|
| `APPLE_CERTIFICATE` | Base64-encoded Developer ID Application `.p12` certificate |
| `APPLE_CERTIFICATE_PASSWORD` | Password protecting the `.p12` file |
| `APPLE_ID` | Apple ID email used for notarization |
| `NOTARYTOOL_PASSWORD` | App-specific password for `xcrun notarytool` |

Export your certificate from Keychain Access as `.p12`, then encode it:

```bash
base64 -i DeveloperID.p12 | pbcopy
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

## Support

CleanKey is free and open source. If it saves you time, you can sponsor development on GitHub.

[![GitHub Sponsors](https://img.shields.io/github/sponsors/istefox?label=Sponsor&logo=GitHub)](https://github.com/sponsors/istefox)

## License

MIT — see [LICENSE](LICENSE).
