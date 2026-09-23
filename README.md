# SimParcel

<img src="Artwork/AppIcon-Source.png" alt="SimParcel app icon" width="128">

**Drag and drop for the iOS Simulator.** Send photos, videos, Live Photos, contacts, `.app` builds, `.apns` push notifications, deep links and any other file to one simulator or to all running simulators at once.

Xcode 27 replaced Simulator.app with Device Hub, which no longer accepts files dropped from Finder. SimParcel is a small native macOS app that brings that workflow back: pick a simulator, drop your files, click **Send to Simulator**. No terminal, no `xcrun simctl addmedia` by hand.

<img src="Artwork/Screenshot.png" alt="SimParcel window with a queue of photos and videos" width="640">

## Features

Drop files or whole folders onto the window, or choose them with **File → Choose Files…** (⌘O):

| You drop | The simulator gets |
| --- | --- |
| Photos and videos | New items in Photos |
| A still image and a video with the same name | One Live Photo |
| `.vcf` contact cards | New contacts |
| `.app` simulator builds | The app, installed |
| `.apns` push payloads | A push notification |
| Web links and deep links | The link, opened (drag it from a browser or use **File → Add Link…**, ⌘L) |
| Any other file (PDF, JSON, ZIP, …) | A copy in **Files → On My iPhone** |

- Send to one simulator, or choose **All Running Simulators** to send everything to each running simulator at once.
- Simulators are grouped by iOS version, and running ones are listed first.
- A simulator that isn't running starts automatically and opens in Simulator.
- Items that are sent leave the queue. Items that fail stay there, show the error, and can be retried.

### Push payloads

A payload needs an `aps` dictionary and a `Simulator Target Bundle` key with your app's bundle ID. The app must be allowed to show notifications in the simulator.

```json
{
  "Simulator Target Bundle": "com.example.MyApp",
  "aps": {
    "alert": { "title": "Hello", "body": "Sent from SimParcel" }
  }
}
```

## Requirements

- macOS 14 or later
- Xcode with at least one iOS Simulator runtime installed
- **Xcode → Settings → Locations → Command Line Tools** set to the Xcode you want to use

## Installation

### Download

Download the latest `SimParcel.zip` from [Releases](../../releases), unzip it, and move the app to `/Applications`.

If a release isn't notarized, macOS blocks it on first launch. To open it anyway, go to **System Settings → Privacy & Security** and click **Open Anyway**, or run:

```bash
xattr -dr com.apple.quarantine "/Applications/SimParcel.app"
```

### Build from source

```bash
git clone https://github.com/<your-account>/SimParcel.git
cd SimParcel
open SimParcel.xcodeproj
```

Run the **SimParcel** scheme on **My Mac**. There are no third-party dependencies.

To build and test from the command line:

```bash
xcodebuild -project SimParcel.xcodeproj -scheme SimParcel -destination 'platform=macOS' test
```

## How it works

The app runs Apple's command line tools:

- `xcrun simctl list devices available --json` lists the simulators.
- `xcrun simctl bootstatus <udid> -b` boots a simulator that isn't running.
- `xcrun simctl addmedia <udid> <files…>` imports photos, videos and contacts. The files of a Live Photo go in a single call, which is how `simctl` pairs them.
- `xcrun simctl install`, `push` and `openurl` handle apps, push payloads and links. Apps are installed first, so pushes and links in the same batch can reach them.
- Other files are copied into the Files app's local storage (the `group.com.apple.FileProvider.LocalStorage` app group, found with `xcrun simctl get_app_container` or, on runtimes where that fails, by its container metadata). Each file is written under a temporary name and then renamed, so Files never shows a partial copy. A name that's taken gets a number: `report 2.pdf`.

Because the app runs `xcrun`, it can't use the App Sandbox and isn't distributed through the Mac App Store.

## Troubleshooting

- **No simulators listed:** check that an iOS runtime is installed (**Xcode → Settings → Components**) and that Command Line Tools point to that Xcode. Then click Refresh (⌘R).
- **Imports go to Photos, not your app:** `addmedia` writes to the simulator's Photos library. Use your app's photo picker to reach the files.
- **A push fails with "isn't allowed to show notifications":** open the app in the simulator and allow notifications first.
- **"The Files app isn't available":** some simulator runtimes don't include Files. Try a simulator with another iOS version.
- **An app fails to install:** only builds for the iOS Simulator work (`Debug-iphonesimulator`), not device builds or `.ipa` files.

## Releasing

`scripts/release.sh` archives the app, signs it with Developer ID, notarizes and staples it, and writes a zip and a DMG to `build/release` with their SHA-256 checksums. It needs a Developer ID Application certificate and notarization credentials stored once in the keychain:

```bash
xcrun notarytool store-credentials "SimParcel" --apple-id "<Apple ID>" --team-id "<Team ID>"
```

## License

[MIT](LICENSE)
