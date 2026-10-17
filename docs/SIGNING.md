# Signing, notarization, and distribution

MouseForge is a non-sandboxed menu-bar app that uses an event tap and HID
access, so it can't go on the Mac App Store. It's distributed directly as a
Developer ID–signed, notarized app.

## 1. Signing for development (current setup)

- **Signing style:** Automatic
- **Team:** `P7RH8T36YW` (Personal Team, viswajith@rapsap.com)
- **Bundle ID:** `com.mouse.forge.MouseForge` (tests: `com.mouse.forge.MouseForgeTests`)
- **Hardened Runtime:** on. **App Sandbox:** off.

This matters for permissions. macOS remembers Accessibility and Input
Monitoring by the app's *designated requirement* (bundle ID plus signing
certificate). An ad-hoc ("Sign to Run Locally") build gets a new identity on
every build, so macOS forgets the permission each time. A team signature
keeps the same identity across rebuilds.

Check the identity of a build:

```sh
codesign -dv --verbose=2 path/to/MouseForge.app        # Authority / TeamIdentifier
codesign -d -r- path/to/MouseForge.app                 # designated requirement
```

After you change the signing identity (for example to Developer ID), grant
the permissions once more. If System Settings shows a stale entry, remove it
with "–" and add the app again.

## 1b. A DMG for your own Mac

```sh
./scripts/make-dmg.sh      # → build/MouseForge-<version>.dmg
```

Builds a universal Release copy signed with the same Apple Development
certificate as the debug builds, so granted permissions carry over, and
packages it with an Applications shortcut. It isn't notarized, so it's for
this Mac; other Macs need the Developer ID route below.

## 2. What you need for distribution

- A paid **Apple Developer Program** membership. A Personal Team can't create
  Developer ID certificates or notarize.
- A **Developer ID Application** certificate. Create it in Xcode ▸ Settings ▸
  Accounts ▸ Manage Certificates ▸ "+".
- An **app-specific password** for your Apple ID (appleid.apple.com), used by
  `notarytool`.

No extra entitlements are needed. The app already declares
`NSAppleEventsUsageDescription`, which AppleScript actions need under the
Hardened Runtime.

## 3. The easy way: Xcode

1. Set the team to your paid team in the target's *Signing & Capabilities*.
2. **Product ▸ Archive**.
3. In the Organizer: **Distribute App ▸ Direct Distribution**. Xcode signs
   with Developer ID, uploads for notarization, waits, and staples the ticket.
4. Export the app and zip it (or put it in a DMG) for distribution.

## 4. The command-line way

```sh
# Archive
xcodebuild -project MouseForge.xcodeproj -scheme MouseForge -configuration Release \
  -archivePath build/MouseForge.xcarchive archive DEVELOPMENT_TEAM=<YOUR_TEAM_ID>

# Export with Developer ID (edit teamID in docs/ExportOptions.plist first)
xcodebuild -exportArchive -archivePath build/MouseForge.xcarchive \
  -exportOptionsPlist docs/ExportOptions.plist -exportPath build/export

# Notarize (store credentials once)
xcrun notarytool store-credentials MouseForgeNotary \
  --apple-id you@example.com --team-id <YOUR_TEAM_ID> --password <app-specific-password>
ditto -c -k --keepParent build/export/MouseForge.app build/MouseForge.zip
xcrun notarytool submit build/MouseForge.zip --keychain-profile MouseForgeNotary --wait

# Staple and verify
xcrun stapler staple build/export/MouseForge.app
spctl -a -vv build/export/MouseForge.app   # expect: accepted, source=Notarized Developer ID
```

If notarization fails, read the log with
`xcrun notarytool log <submission-id> --keychain-profile MouseForgeNotary`.

## 5. Launch at login

"Open MouseForge at login" uses `SMAppService.mainApp`. It works best when
the app lives in `/Applications`. If macOS asks for approval, the General
screen links to System Settings ▸ General ▸ Login Items.

## 6. Private API note

`CoreDockSendNotification` (Mission Control, App Exposé, Show Desktop,
Launchpad) is looked up at runtime. Each use has a public fallback. Private
API use is fine for direct distribution and is checked neither by
notarization nor by Gatekeeper.
