# Selection Tools plugin

Selection Tools now owns one local action: **Search Selected Text**. Translation, definition and
grammar checking moved to AI Chat so their results can continue as conversations; see
[`ai-chat.md`](ai-chat.md).

The Search action keeps its stable `selection-tools.search` ID, launcher command and persisted
shortcut key. It ships unbound; Settings recommends Hyper + S.

## Selection capture

`AppCore` owns the shared `SelectedTextCapture` in `Core/SelectedTextCapture.swift`. Selection Tools
and AI Chat both use it, so disabling Selection Tools does not disable AI Chat's selected-text
actions. A shortcut snapshots `NSWorkspace.shared.frontmostApplication` synchronously before the
first `await`, then captures in tiers:

1. `SelectedTextReader` reads the focused control through Accessibility.
2. Chromium accessibility attributes are enabled temporarily and retried while its tree appears.
3. A guarded synthetic ⌘C snapshots and restores the pasteboard when canvas or web surfaces expose
   no Accessibility selection.

The fallback is suppressed from clipboard history for its whole lifetime and stamps the restored
pasteboard with Spotter's internal marker. Captured snapshots keep only the selected text, source PID,
app name, bundle identifier and capture time; the selected text is never logged.

Launcher commands first hide the palette through the existing focus-restoration path, then retry only
transient missing-frontmost-app states. `previousApplication` remains a focus destination, never a
source of selection data.

## Search and failure UI

`SearchURLBuilder` stays Foundation-only. It trims only outer whitespace and creates an HTTPS Google
Search URL with `URLComponents` and one `q` query item. Spotter does not request Google itself;
`NSWorkspace` hands the URL to the default browser.

Capture, URL construction and browser-open failures remain explicit on the plugin's shared palette
screen. The plugin creates no window, search field, list chrome or network request. Disabling it
removes Search from the launcher, makes its shortcut a no-op and returns an active failure screen to
the launcher.
