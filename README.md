# Simulator Media Drop

<img src="Artwork/AppIcon-Source.png" alt="Simulator Media Drop app icon" width="128">

A small macOS app that sends photos, videos, Live Photos, contacts, apps, push notifications and links to iOS Simulators.

Dragging files onto a simulator window stopped working reliably in Xcode 27's Device Hub. This app brings that workflow back without the terminal: pick a simulator, drop your files, click **Send to Simulator**.

<img src="Artwork/Screenshot.png" alt="Simulator Media Drop window with a queue of photos and videos" width="640">

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
    "alert": { "title": "Hello", "body": "Sent from Simulator Media Drop" }
  }
}
```

## Requirements

- macOS 14 or later
- Xcode with at least one iOS Simulator runtime installed
- **Xcode → Settings → Locations → Command Line Tools** set to the Xcode you want to use

## Installation

### Download

Download the latest `SimulatorMediaDrop.zip` from [Releases](../../releases), unzip it, and move the app to `/Applications`.

If a release isn't notarized, macOS blocks it on first launch. To open it anyway, go to **System Settings → Privacy & Security** and click **Open Anyway**, or run:

```bash
xattr -dr com.apple.quarantine "/Applications/SimulatorMediaDrop.app"
```

### Build from source

```bash
git clone https://github.com/<your-account>/SimulatorMediaDrop.git
cd SimulatorMediaDrop
open SimulatorMediaDrop.xcodeproj
```

Run the **SimulatorMediaDrop** scheme on **My Mac**. There are no third-party dependencies.

To build and test from the command line:

```bash
xcodebuild -project SimulatorMediaDrop.xcodeproj -scheme SimulatorMediaDrop -destination 'platform=macOS' test
```

## How it works

The app runs Apple's command line tools:

- `xcrun simctl list devices available --json` lists the simulators.
- `xcrun simctl bootstatus <udid> -b` boots a simulator that isn't running.
- `xcrun simctl addmedia <udid> <files…>` imports photos, videos and contacts. The files of a Live Photo go in a single call, which is how `simctl` pairs them.
- `xcrun simctl install`, `push` and `openurl` handle apps, push payloads and links. Apps are installed first, so pushes and links in the same batch can reach them.

Because the app runs `xcrun`, it can't use the App Sandbox and isn't distributed through the Mac App Store.

## Troubleshooting

- **No simulators listed:** check that an iOS runtime is installed (**Xcode → Settings → Components**) and that Command Line Tools point to that Xcode. Then click Refresh (⌘R).
- **Imports go to Photos, not your app:** `addmedia` writes to the simulator's Photos library. Use your app's photo picker to reach the files.
- **A push fails with "isn't allowed to show notifications":** open the app in the simulator and allow notifications first.
- **An app fails to install:** only builds for the iOS Simulator work (`Debug-iphonesimulator`), not device builds or `.ipa` files.

## License

[MIT](LICENSE)
