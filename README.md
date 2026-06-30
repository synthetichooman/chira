# Chira

Chira is a lightweight native macOS clipboard history overlay that lives around the top-center notch area.

Version: `0.1`

## Run

```sh
Scripts/run-app.sh
```

For a quick local smoke check:

```sh
Scripts/smoke-check.sh
```

The app is bundled at:

```text
.build/Chira.app
```

It runs as an accessory app, so it will not appear in the Dock. Use the menu bar capsule icon to show, recenter, or quit.

## v0.1

- Native AppKit overlay for recent clipboard items
- Hidden by default, revealed from the notch or top-center hot zone
- Text clipboard items can be clicked to copy again
- Image clipboard items are stored as PNG/TIFF data and can be clicked to copy again
- Image hover previews are off by default to keep memory lower

## Source Layout

```text
Sources/Chira/
  AppDelegate.*          App lifecycle, screen positioning, timers, menu item
  IslandView.*           Clipboard overlay rendering, hit testing, row state
  ClipboardHistoryItem.* Clipboard text/image capture and pasteboard restore
  ChiraConstants.*       Shared enums and display text helpers
  main.m                 App entry point
```

## Notes

Chira is currently a personal/local MVP. It is clipboard-only and is not signed or notarized for distribution.
