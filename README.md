<div align="center">

# ✉️ Xyecoc Mail for iOS

**A native, lightweight, and modern iOS mail client for xyecoc.com built with SwiftUI.**

[English](#-about-the-project) | [Русская версия](assets/ru_readme.md) | [📚 Wiki Documentation](https://github.com/ziahka/xyecoc-ipa/wiki) | [VirusTotal](https://www.virustotal.com/gui/file/f9ad2ee044d3f26f42c33ddd5392007cd19ea12aaa54781003a21888f9a57a47?nocache=1)

---

</div>

## 📌 About the Project

**Xyecoc Mail for iOS** is an independent, native mail client crafted specifically for iPhone users running **iOS 16.0 or later**. It serves as a direct alternative to the original Android application, delivering an ergonomic, high-performance experience without running inside web wrappers or browser tabs.

The project connects directly to the official backend endpoints (`api.xyecoc.com` for JSON-RPC requests and `cdn.xyecoc.com` for HTML mail contents and attachments).

---

## ✨ Features Overview

* **Multi-Account Management:** Add and manage up to 15 independent mailboxes. Each account maintains its own isolated database cache and authentication state.
* **Zero Dependencies Architecture:** Built exclusively using Apple's system frameworks (`SwiftUI`, `Foundation`, `Security`, `WebKit`). No CocoaPods, Carthage, or third-party Swift Packages to resolve.
* **Offline Storage & Caching:** All fetched threads, folders, and read messages are cached locally using thread-safe Swift actors, allowing instant access in Airplane mode.
* **Full HTML Rendering:** Rich email rendering via an isolated WebKit engine that enforces sandboxed security, proper dark/light theme matching, and correct image display.
* **Attachments Support:** Native export and download through the iOS Share Sheet and seamless upload of photos and documents via `PhotosPicker` and `UIDocumentPicker`.
* **Hardware Security:** Sensitive tokens and credentials are encrypted and stored in the secure iOS **Keychain**.
* **Two-Factor Authentication (2FA):** Integrated authentication state machine supporting standard 6-digit 2FA verification flow.
* **OTP Code Detection:** When a letter contains a verification code, the reader shows a one-tap "copy code" chip; the clipboard is auto-erased after 60 seconds.
* **Attachment Downloads:** Any attachment can be downloaded and handed to the native share sheet (save to Files, Photos, etc.) in addition to opening it in the browser.
* **Local Mail Statistics:** A per-account dashboard built from the offline cache — totals, a 7-day activity chart, and the top senders.
* **Privacy Controls:** Optional content-blocker rules stop remote tracking pixels in emails (service CDN images keep loading), plus a configurable reading font size and an unread-count home-screen badge.
* **Snoozed Mail:** Hide a message from the lists until a chosen moment (1 hour, evening, tomorrow morning, a week) — it comes back on its own; a virtual "Snoozed" folder with a badge and one-tap unsnooze.
* **Sender Blacklist:** Locally blocked addresses disappear from every list instantly, on top of the server-side block; the list is managed in Settings.
* **Smart Locking:** The PIN is stored as PBKDF2-SHA256 with a random salt (legacy hashes migrate transparently), and the auto-lock delay is configurable: immediately, 1, 5 or 15 minutes.
* **Reliability & Polish:** Polling refreshes the folder you are actually viewing, drafts autosave only when changed, cache writes are coalesced, batch actions run in parallel, destructive actions ask for confirmation, and attachments download without leaking the token to the browser.
* **Make It Yours:** List density, snippet preview, date grouping (Today / Yesterday / Earlier), sorting, assignable swipe actions, undo-send with a countdown, send confirmation, a start folder, refresh interval, badge scope (inbox or all folders), a privacy shield for the app switcher, custom snooze date, and a haptics switch — all in Settings.

---

## 📲 Step-by-Step Installation Guide

Because this application is not distributed through the App Store, it is installed via **Sideloading** (signing the `.ipa` with your personal Apple ID).

### 1. Download the Pre-built `.ipa`
1. Navigate to the **[Actions](https://github.com/ziahka/xyecoc-ipa/actions)** tab of this repository.
2. Click on the latest workflow run marked with a **green checkmark** (✅).
3. Scroll down to the **Artifacts** section at the bottom.
4. Download the **`XyecocMail-unsigned`** ZIP archive and extract it on your computer to get `XyecocMail-unsigned.ipa`.

---

### 2. Sideload to your iPhone

#### Method A: Sideloadly (Windows / macOS) — Recommended
1. Download and install [Sideloadly](https://sideloadly.io/).
2. On Windows, ensure standard [iTunes](https://www.apple.com/itunes/) is installed (do not use the Microsoft Store version).
3. Connect your iPhone via USB cable, unlock it, and select **Trust This Computer**.
4. Drag and drop `XyecocMail-unsigned.ipa` into Sideloadly.
5. Enter your Apple ID email address.
6. Click **Start** and provide your credentials when prompted by Apple's verification servers.
7. Wait until the log displays `Done`. The app icon will appear on your Home Screen.

#### Method B: AltStore (Automated Wi-Fi Refresh)
1. Install [AltServer](https://altstore.io/) on your PC/Mac.
2. Connect your iPhone via USB and install the **AltStore** app onto your device.
3. Transfer `XyecocMail-unsigned.ipa` to your iPhone (via AirDrop, iCloud Drive, or Telegram).
4. Open the AltStore app on your phone, go to **My Apps**, tap the **+** icon, and select the `.ipa` file.

#### Method C: TrollStore (iOS 14.0 – 16.6.1 / 17.0)
1. Transfer the `.ipa` file to your device.
2. Tap the Share button and select **TrollStore** for permanent installation without 7-day expiration.

---

### 3. Trust the Developer Profile (First Launch)
When opening the app for the first time, iOS will display an **"Untrusted Developer"** prompt:
1. Open **Settings** on your iPhone.
2. Navigate to **General** → **VPN & Device Management**.
3. Under *Developer App*, select your Apple ID.
4. Tap **Trust "[Your Apple ID]"** and confirm.
5. Launch **Xyecoc Mail** from your Home Screen.

---

## ⚙️ Sideloading Limitations

* **7-Day Expiration:** Free Apple IDs issue certificates valid for 7 days. Once expired, simply re-install the `.ipa` with Sideloadly or refresh via AltStore (your cached data and settings will be preserved).
* **Push Notifications:** Due to Apple security policies, background APNs push notifications are unavailable on free developer accounts. Mail syncs upon opening the app or during iOS Background App Refresh cycles.

---

## 🛠 Local Development (macOS)

```bash
# 1. Install XcodeGen
brew install xcodegen

# 2. Generate the .xcodeproj
xcodegen generate

# 3. Open in Xcode
open XyecocMail.xcodeproj
