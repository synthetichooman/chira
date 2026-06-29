# Chira

Chira is a tiny personal macOS notch overlay. The name comes from the Japanese idea of a quick glance.

Version: `0.1`

## Run

```sh
Scripts/run-app.sh
```

The app is bundled at:

```text
.build/Chira.app
```

It runs as an accessory app, so it will not appear in the Dock. Use the menu bar capsule icon to show, recenter, or quit.

## v0.1

- Native AppKit overlay anchored to the Mac notch
- Hidden by default, revealed from the notch hot zone
- Clipboard history focused UI
- Text clipboard items can be clicked to copy again
- Image clipboard items are stored as PNG/TIFF data and can be clicked to copy again

## Source Layout

```text
Sources/Chira/
  AppDelegate.*          App lifecycle, notch positioning, timers, menu item
  IslandView.*           Overlay rendering, hit testing, pressed row state
  IslandModule.*         Small view model for content rendered in the island
  ClipboardHistoryItem.* Clipboard text/image capture and pasteboard restore
  ChiraConstants.*       Shared enums, identifiers, and display text helpers
  main.m                 App entry point
```

## Notes

Chira is currently a personal/local build. It is not signed or notarized for distribution.
