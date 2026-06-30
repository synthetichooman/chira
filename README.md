# Chira

Chira is a lightweight macOS clipboard history overlay that lives around the top-center notch area.

Version: `0.1`

## Run

Build and open Chira:

```sh
Scripts/run-app.sh
```

open it yourself:

```sh
open .build/Chira.app
```

Chira runs as an accessory app, so it will not appear in the Dock. After opening it, use the menu bar capsule icon or move the pointer to the notch/top-center hot zone.

## Package

Build a local DMG:

```sh
Scripts/package-dmg.sh
```

The packaged app is written to `.build/Chira.app`, and the DMG is written to `.build/Chira-0.1.dmg`.

For a quick local smoke check:

```sh
Scripts/smoke-check.sh
```

## v0.1

- Native AppKit overlay for recent clipboard items
- Hidden by default, revealed from the notch or top-center hot zone
- Text clipboard items can be clicked to copy again
- Image clipboard items are stored as PNG/TIFF data and can be clicked to copy again
- Image hover previews are off by default to keep memory lower
- Settings shows the app version/build and local git revision
- Settings can register Chira to open at login
- First launch for a version adds patch notes to the top of Chira's clipboard history
- Island header controls open settings or quit Chira

## Source Layout

```text
Resources/
  AppIcon.icns           macOS app icon
  AppIconSource.png      Source image used to generate AppIcon.icns
  Info.plist             macOS app bundle metadata

Scripts/
  build-app.sh           Compile and bundle .build/Chira.app
  package-dmg.sh         Build .build/Chira-0.1.dmg
  run-app.sh             Build, relaunch, and open Chira locally
  smoke-check.sh         Build, launch, report RSS/CPU, and capture a screenshot

Sources/Chira/
  AppDelegate.h          App delegate interface
  AppDelegate.m          App lifecycle, screen positioning, timers, settings, menu item
  ChiraConstants.h       Shared enum declarations
  ChiraConstants.m       Shared display text helpers
  ClipboardHistoryItem.h Clipboard history model interface
  ClipboardHistoryItem.m Clipboard text/image capture and pasteboard restore
  IslandView.h           Clipboard overlay view/delegate interface
  IslandView.m           Clipboard overlay rendering, hit testing, row state
  main.m                 App entry point
```

## Notes

Chira is currently a personal/local MVP. It is clipboard-only and is not signed or notarized for distribution.
