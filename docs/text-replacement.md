# Text Replacement plugin

Text Replacement expands user-defined triggers into reusable text in the currently focused text
field. A prefix is shared by every pair: with prefix `@@`, keyword `gmail` and replacement
`abc@gmail.com`, typing `@@gmail` immediately removes the trigger and types the replacement.
Matching is case-insensitive, while replacement text is inserted exactly as saved.

## Lifecycle and permission

The plugin ships enabled but idle: the tap only installs once at least one rule exists and the
Accessibility grant is present, so the default state observes nothing. Its registration declares
Accessibility so System → Permissions lists the dependency.
`TextReplacementManager` installs a modifying session event tap only while the plugin is enabled and
at least one rule exists. Disabling the plugin, deleting the last rule, ending the user session or
revoking Accessibility tears down or disables the tap. A one-second health check retries after the
user grants permission and revives a system-disabled tap.

`AppCore` owns the one `TextReplacementStore` and one `TextReplacementManager`; the plugin registry's
lifecycle closures only start and stop that manager. There is no helper process, runtime bundle or
separate window.

## Matching and replacement

`TextReplacementEngine` is Foundation-only and pure. It does not retain an input history: after each
character it keeps only the longest suffix that is still a prefix of a configured trigger. Unrelated
text immediately reduces the buffer to empty. Mouse clicks, navigation keys and modified shortcuts
reset the suffix; Backspace removes one pending character.

Keywords are case-insensitive, contain no whitespace and cannot duplicate or prefix another keyword.
That last rule makes immediate expansion deterministic — `g` and `gmail` cannot both exist because
the shorter trigger would otherwise fire before the longer one could be completed.

When a trigger matches, the original key event finishes normally. On the next main-runloop turn the
manager posts one synthetic Backspace per trigger character, followed by Unicode keyboard events for
the replacement. These events carry the same source marker used by Hyper Key, so neither event tap
reacts to or rewrites them. The clipboard is never read or changed.

## Persistence and Settings

The prefix defaults to `@@`; rules start empty. `TextReplacementStore` persists both values in the
application's bundle-scoped `UserDefaults` domain under `text-replacement.prefix` and
`text-replacement.rules`. The Settings page contains the standard Plugin toggle, prefix editor,
privacy and permission guidance, and add/edit/delete controls for any number of keyword/replacement
pairs. Replacement values may be multiline and are limited to 10,000 characters.

## Testing

Run the standalone harness without installing an event tap:

```sh
swiftc -swift-version 6 Spotter/Plugins/TextReplacement/TextReplacementEngine.swift \
    Spotter/Plugins/TextReplacement/TextReplacementStore.swift Tools/text-replacement-test.swift \
    -o /tmp/text-replacement-test && /tmp/text-replacement-test
```
