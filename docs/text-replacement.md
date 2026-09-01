# Snippets plugin

Snippets are named pieces of reusable text: searched and pasted from the palette's **Search
Snippets** screen, and — when a snippet carries an optional expansion keyword — expanded in any
text field as you type, the original Text Replacement behavior. The plugin keeps its historical
`text-replacement` identity (plugin ID, permission wiring, preference keys) so enable state,
shortcuts and stored data survive the reshape; only the model and surfaces grew.

A prefix is shared by every keyword: with prefix `@@` and keyword `gmail` on a snippet holding
`abc@gmail.com`, typing `@@gmail` immediately removes the trigger and types the snippet. Matching is
case-insensitive, while snippet text is inserted exactly as saved. A snippet without a keyword is
palette-only and never touches typing.

## The palette screen

`PluginPaletteScreenRegistration` rendered by the shared list: rows show the snippet's name over a
one-line content preview, with keyworded snippets wearing a `prefix+keyword` accessory chip. ↵
pastes into the app the palette was summoned from, ⌘↵ copies, and the ⌘K menu adds both plus a jump
to Settings. Search matches names, content and keywords.

## Model and migration

`Snippet { id, name, content, keyword? }` decodes both its own shape and the retired
`TextReplacementRule { id, keyword, replacement }` records — a legacy rule becomes an expanding
snippet named after its keyword, in place, under the same `text-replacement.rules` defaults key.
Settings backups keep their `textReplacement.rules` field name for the same reason; old backups
import, and new backups' keywordless snippets are simply dropped by old app versions.

## Lifecycle and permission

The plugin ships enabled. The event tap only installs once at least one *keyworded* snippet exists
and the Accessibility grant is present, so the default state observes nothing; palette search and
paste never need the tap. Its registration declares Accessibility so System → Permissions lists the
dependency. `TextReplacementManager` installs a modifying session event tap only while the plugin is
enabled; disabling the plugin, ending the user session or revoking Accessibility tears down or
disables the tap. A one-second health check retries after the user grants permission and revives a
system-disabled tap.

`AppCore` owns the one `TextReplacementStore` and one `TextReplacementManager`; the plugin registry's
lifecycle closures only start and stop that manager. There is no helper process, runtime bundle or
separate window.

## Matching and expansion

`TextReplacementEngine` is Foundation-only and pure, built from the keyworded snippets only. It does
not retain an input history: after each character it keeps only the longest suffix that is still a
prefix of a configured trigger. Unrelated text immediately reduces the buffer to empty. Mouse
clicks, navigation keys and modified shortcuts reset the suffix; Backspace removes one pending
character.

Keywords are case-insensitive, contain no whitespace and cannot duplicate or prefix another keyword.
That last rule makes immediate expansion deterministic — `g` and `gmail` cannot both exist because
the shorter trigger would otherwise fire before the longer one could be completed. Palette-only
snippets never conflict with anything.

When a trigger matches, the original key event finishes normally. On the next main-runloop turn the
manager posts one synthetic Backspace per trigger character, followed by Unicode keyboard events for
the snippet. These events carry the same source marker used by Hyper Key, so neither event tap
reacts to or rewrites them. Expansion never reads or changes the clipboard (palette copy/paste, an
explicit user action, goes through `Paster` like every other palette paste).

## Persistence and Settings

The prefix defaults to `@@`; snippets start empty. `TextReplacementStore` persists both in the
application's bundle-scoped `UserDefaults` domain under `text-replacement.prefix` and
`text-replacement.rules`. The Settings pane holds the standard Plugin toggle, the snippet list with
add/edit/delete (name, multiline content up to 10,000 characters, optional keyword), and the
expansion prefix. The Accessibility callout appears only when a keyworded snippet actually needs it.

## Testing

Run the standalone harness without installing an event tap:

```sh
swiftc -swift-version 6 Spotter/Plugins/TextReplacement/TextReplacementEngine.swift \
    Spotter/Plugins/TextReplacement/TextReplacementStore.swift Tools/text-replacement-test.swift \
    -o /tmp/text-replacement-test && /tmp/text-replacement-test
```
