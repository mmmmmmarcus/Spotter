# Selection Tools plugin

Selection Tools owns two selected-text actions: **Search Selected Text** and **Translate Selected
Text**. Search opens Google Search in the default browser. Translate calls Google Cloud Translation
Basic and presents exactly three selectable rows in this order: the original text, Simplified
Chinese and English. Every completed row copies its own text with Enter.

The actions retain the stable `selection-tools.search` / `selection-tools.translate` shortcut IDs
and `command:selection-tools:*` launcher command IDs. Existing Hyper + T bindings survive the move
back from AI Chat because the translation action also keeps its original
`KeyboardShortcuts_plugin.selection-tools.translate` defaults key. New installs ship unbound;
Settings recommends Hyper + S and Hyper + T.

## Selection capture

`AppCore` owns the shared `SelectedTextCapture` in `Core/SelectedTextCapture.swift`. Selection Tools
and AI Chat both use it. A shortcut snapshots `NSWorkspace.shared.frontmostApplication`
synchronously before the first `await`, then captures in tiers:

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
Search URL with `URLComponents` and one `q` query item. Spotter does not request Google itself;
`NSWorkspace` hands the URL to the default browser.

Capture, URL construction and browser-open failures render on the plugin's shared palette screen.

## Translation

`SelectionToolsManager` owns the Google translation configuration, request lifecycle and result
state. Translation ships off. The user must explicitly enable it in Selection Tools settings and
provide a Google Cloud API key. The consent dialog names Google Cloud Translation Basic, explains
that each action makes two billable requests and states that Spotter does not cache the selected text
or translations. The manager re-checks both consent and the current key after every request returns.

The API key and consent flag live in bundle-scoped `UserDefaults` and enter the trusted
`SettingsBackup` v3 snapshot, so clearing the key or changing consent propagates through sync.
Requests use a private ephemeral `URLSession` with no URL cache and a fixed HTTPS
Cloud Translation Basic v2 endpoint. Spotter sends the selected text concurrently with targets
`zh-CN` and `en`; the API auto-detects the source language. A settings button validates the key with
one short request.

The palette switches immediately to a three-row loading snapshot so the original remains visible.
When both responses arrive, `SelectionToolsResults` preserves the original → Simplified Chinese →
English row order required by the flat selection index. The shared `PluginPaletteList` owns
selection, filtering, scrolling and Enter activation; the plugin creates no custom window or list.
Failures replace the rows with the provider or capture error.

Disabling translation cancels the active request and clears its in-memory result while preserving
the locally stored key. Disabling the plugin cancels its active work, removes both commands, makes
both shortcuts no-ops and returns an active plugin screen to the launcher.
