# Xyecoc Mail — iOS (SwiftUI)

A native SwiftUI port of the Android `com.xyecoc.mail` client, talking to the
same backend (`api.xyecoc.com` JSON-RPC + `cdn.xyecoc.com`). This repo currently
contains the **foundation layer**: models, Keychain, networking, auth + 2FA, and
a functional login screen you can build into an unsigned `.ipa` and sideload.

## Project structure

```
xyecoc-ipa/
├── project.yml                     # XcodeGen spec → generates XyecocMail.xcodeproj
├── .github/workflows/build-ios.yml # CI: builds an unsigned .ipa on macOS runners
├── Sources/
│   ├── XyecocMailApp.swift         # @main entry point
│   ├── ContentView.swift           # AuthViewModel + Login / 2FA / logged-in views
│   └── Core/
│       ├── Models.swift            # Codable models + JSONValue + RequestPayload/ApiResponse
│       ├── KeychainManager.swift   # token/email storage (replaces SecurePrefs)
│       ├── Networking/
│       │   └── ApiClient.swift     # URLSession port of ApiService.kt
│       └── Repository/
│           └── AuthRepository.swift# auth + 2FA flow
```

`XyecocMail.xcodeproj` and `Generated/` are **not committed** — XcodeGen
regenerates them (locally and in CI) so there's no fragile `.pbxproj` to merge.

## Zero third-party dependencies

The foundation uses only `Foundation`, `Security`, and `SwiftUI`. Nothing to
resolve — it builds as-is. (Socket.IO, GRDB, etc. arrive with the inbox layer.)

## Build the `.ipa` (CI — the "push and download" path)

1. Create a fresh GitHub repo and push this tree to it.
2. The `build-ios` workflow runs automatically on push (or trigger it from the
   **Actions** tab → *build-ios* → *Run workflow*).
3. When it finishes, download the **`XyecocMail-unsigned`** artifact — that's your
   unsigned `.ipa`.
4. Sign + install it with **Sideloadly** or **AltStore** (they apply your Apple ID
   signature on-device). See the free-account limits (7-day expiry, 3-app cap) in
   the project notes.

## Build locally (optional, needs a Mac + Xcode)

```bash
brew install xcodegen
xcodegen generate
open XyecocMail.xcodeproj   # ⌘R to run in the Simulator
```

## Test authentication against the live backend

Run the app, enter a mailbox name (it auto-appends `@xyecoc.com`) and password:

- **status == 1** → token saved to Keychain, "Авторизация успешна" screen.
- **status == 2** → routed to the 2FA screen (`account/2fa-check`).
- error → the backend `message` is shown inline.

The `#if DEBUG` logging in `ApiClient` prints every request/response to the
Xcode console so you can watch the RPC round-trip.

## Next milestones

1. Inbox — GRDB cache (Room parity) + `mail/default` paging & folder sync.
2. Reader — `WKWebView` + `fetchMailBodyHtml` (already implemented in `ApiClient`).
3. Compose/send — `message-new` with base64 attachments.
4. Realtime — `socket.io-client-swift` (foreground only on iOS).
5. Settings/Support — profile, 2FA setup, folders/tags/filters/aliases.
