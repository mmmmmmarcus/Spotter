# Search plugin (directory `SelectionTools/`)

Search owns one action — **Search Selected Text** — which reads the text selected in the frontmost
app and opens a Google Search for it in the default browser. Spotter never requests Google itself.

Display-renamed from Selection Tools (Sep 2026), when everything Google-Translate moved into its own
[Translate](translate.md) plugin and searching was all that remained. The `PluginID` stays
`selection-tools` and the source directory stays `Plugins/SelectionTools/`, following the same
judgement as Snippets and Caffeinate: the persisted preferences,
the `KeyboardShortcuts_plugin.selection-tools.search` binding and the
`command:selection-tools:search` launcher command all key off that identity, so renaming it would
silently read as unbound. The action resolves its recorder through `AppEntry.hotKeyAction`; new
installs ship it unbound, and Settings recommends Hyper + S.

Definition and grammar actions are **not** here and never were moved back: they belong to
[AI Chat](ai-chat.md), which kept their original `selection-tools.*` defaults keys.

## Selection capture

`AppCore` owns the shared `SelectedTextCapture` in `Core/SelectedTextCapture.swift`. Search,
Translate and AI Chat all use it. The Notes editor explicitly opts its native `NSTextView` into local
capture, so a selection inside Spotter Notes is read directly without Accessibility or the
pasteboard; other Spotter fields remain excluded. The selection is snapshotted before the palette
takes focus, which keeps launcher commands as well as global shortcuts working from Notes.
External-app capture snapshots `NSWorkspace.shared.frontmostApplication` synchronously before the
first `await`, then captures in tiers:

1. `SelectedTextReader` reads the focused control through Accessibility.
2. Chromium accessibility attributes are enabled temporarily and retried while its tree appears.
3. A guarded synthetic ⌘C snapshots and restores the pasteboard when canvas or web surfaces expose
   no Accessibility selection.

The fallback is suppressed from clipboard history for its whole lifetime and stamps the restored
pasteboard with Spotter's internal marker. Captured snapshots keep only the selected text, source
PID, app name, bundle identifier and capture time; the selected text is never logged.

Launcher commands first hide the palette through the existing focus-restoration path, then retry
only transient missing-frontmost-app states. `previousApplication` remains a focus destination,
never a source of selection data.

## Search

`SearchURLBuilder` stays Foundation-only. It trims only outer whitespace and creates an HTTPS Google
Search URL with `URLComponents` and one `q` query item. `NSWorkspace` hands the URL to the default
browser.

## The palette screen

A successful search leaves for the browser, so the plugin's palette screen exists only for the
failures: a capture that found no selection, a URL that could not be built, a browser that would not
open it. `SelectionToolsResults.snapshot` therefore never produces rows — only a section title and a
message naming the step that could not be taken — and the screen has no primary action. It is still a
registered `PluginPaletteScreenRegistration` using the shared `PluginPaletteList`, not a window or an
alert of its own.

`Tools/selection-tools-test.swift` compiles the real `SearchURLBuilder` and `SelectionToolsResults`
and pins both: query encoding round-trips (including CJK, emoji and reserved characters) and the
rowless idle/failure screens.

Leaving the screen returns an active plugin
screen to the launcher.
