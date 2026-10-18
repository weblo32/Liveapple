# Classora Builds Directory

This directory stores generated release APKs for the Classora Flutter application.

## Rules
- All `*.apk` files in this directory are ignored by Git (per `.gitignore`).
- Only this `README.md` is committed and tracked.
- Each build produces a universal release APK: `Classora-<yyyyMMdd-HHmm>.apk`.

## Latest Release Build Information

- **Release Build (Screen share hidden on Android):**
  - **File:** `C:\Users\Admin\Desktop\Classora_Updated_APKs\Classora-Latest.apk` (and `Classora-Release.apk`)
  - **Date:** 2026-10-18 19:48 IST
  - **App Version:** `2.0.0+1`
  - **File Size:** 114,519,579 bytes (~109.2 MB)
  - **SHA-256 Checksum:** `A7186C96A8A9072E2A8157A809CEF223F51879A9FA43AA56FB7508B9E91AD938`

- **Screen Share Test Build (`ENABLE_ANDROID_SCREEN_SHARE=true`):**
  - **File:** `C:\Users\Admin\Desktop\Classora_Updated_APKs\Classora-SCREENSHARE-TEST.apk`
  - **Date:** 2026-10-18 19:55 IST
  - **App Version:** `2.0.0+1`
  - **File Size:** 114,519,579 bytes (~109.2 MB)
  - **SHA-256 Checksum:** `C99566F058AE425CC263F5E59866C223E794184CE9D882B3C09338E470489DA2`
  - **Description:** Compiled specifically for physical phone testing with screen share enabled.

### Client Experience & Zero-Configuration Architecture
- **100% Zero URL Configuration:** Clients and users never have to paste, type, or configure any server URL.
- **Server Settings Gear Hidden:** The ⚙️ settings icon is hidden in release mode so clients see a completely clean, professional login screen.
- **Secret Developer Access:** Developers and QA can tap the Classora "C" logo 5 times to reveal the server diagnostics modal if needed.
- **Dynamic Cloud Sync:** On startup, the app automatically checks `server_config.json` for live endpoint updates without requiring APK re-installs.
- **Primary Backend URL (Active):** `https://nelson-consist-feels-applicable.trycloudflare.com/api`
- **Video Stream SFU:** LiveKit Cloud via server-issued signed JWT tokens.
- **Runtime Database:** Local SQLite (`dev.db`).
