# Emoji picker

A palette sub-screen (reached like Clipboard / Calculator History) presenting a searchable emoji grid.
It is a built-in plugin: the catalog loads lazily when enabled, its launcher command and shortcut are
routed through `PluginRegistry`, and disabling it returns an open emoji palette to the launcher.

## Layout

- `Spotter/Plugins/EmojiSymbols/` owns the entire native plugin:
  - `EmojiSymbolsPlugin.swift` — registration, commands, shortcut and lifecycle wiring.
  - `EmojiCatalog.swift` — the catalog model (groups, names, keywords).
  - `EmojiGridGeometry.swift` — pure flat-index keyboard navigation math (up/down across ragged
    sectioned rows); cell sizing lives in `Theme.Size` and `EmojiGridView`.
  - `EmojiData.generated.swift` — the emoji dataset.
  - `EmojiIndex.swift` — search index over the catalog.
  - `FrequentEmojiStore.swift` — persisted most-recently / frequently used emoji.
  - `EmojiGridView.swift` and `EmojiSettingsView.swift` — the SwiftUI feature surfaces.

`EmojiCatalog.swift`, `EmojiGridGeometry.swift` and the generated dataset form the
**Foundation-only** testable boundary; the other files may use AppKit or SwiftUI as required.
The bounded `FrequentEmojiStore` records enter trusted v3 backups and automatic sync, so usage
ranking and resets propagate between Macs.

## Invariants

- **`EmojiData.generated.swift` is emitted by `node Tools/gen-emoji.js`** (Node 18+ for global
  `fetch`) — **never edit it by hand**. Regenerate and commit instead.
- **`EmojiCatalog.swift` and `EmojiGridGeometry.swift` must stay AppKit/SwiftUI-free**, because the
  `Tools/emoji-test.swift` harness compiles the real sources:

  ```sh
  swiftc Spotter/Plugins/EmojiSymbols/EmojiCatalog.swift \
    Spotter/Plugins/EmojiSymbols/EmojiGridGeometry.swift \
    Spotter/Plugins/EmojiSymbols/EmojiData.generated.swift Tools/emoji-test.swift \
    -o /tmp/emoji-test && /tmp/emoji-test
  ```

- The grid list uses the palette scrollbar (`.thinScrollbar()` + `.hideNativeScrollers()`) and the
  shared `SectionHeader` for group labels — see [ui.md](ui.md).
