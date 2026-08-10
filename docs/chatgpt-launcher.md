# Send to ChatGPT

Send to ChatGPT is a native, enabled-by-default plugin that hands one prompt from Spotter to a new
chat in the current ChatGPT desktop app for macOS. It is separate from Spotter's built-in AI Chat:
it uses the user's signed-in ChatGPT app and does not use the OpenRouter key.

## Interaction

`Send to ChatGPT` is a launcher command and an optional global shortcut. It opens a registered
plugin palette screen using the shared Spotter search field and `PluginPaletteList`. The query
becomes one selectable prompt row; pressing Return starts the handoff and dismisses Spotter without
restoring the previously focused app.

The plugin requires the current official ChatGPT app, whose `codex://new?prompt=…` deep link creates
a new local chat and preloads the composer. The prompt is encoded with `URLComponents`; Spotter does
not put it on the clipboard, store it, or include it in diagnostics.

## Safe submission

The deep link deliberately performs only the documented prefill. Automatic submission is a separate,
Accessibility-gated step:

1. Spotter resolves the registered `codex` handler and requires the official ChatGPT bundle
   identifier.
2. `ChatGPTLauncherCoordinator` opens the deep link, waits for the ChatGPT process and opts its
   Chromium accessibility tree in for the duration of the attempt.
3. The automation accepts only the system-wide focused element owned by that ChatGPT process, with
   an editable text role and a full value matching the prepared prompt.
4. Only that verified state receives a Return key event targeted to the ChatGPT process.

The check is bounded to ten seconds and is cancelled when the plugin is disabled or a newer handoff
starts. If the app opens but the composer cannot be verified, Spotter posts no key event: ChatGPT
keeps the prefilled text as an unsent draft and a HUD tells the user to press Return manually.

## Ownership and permissions

`AppCore` owns the single `ChatGPTLauncherCoordinator`; it retains only the current cancellable task
and has no persisted state. Plugin enablement and the optional shortcut use the standard registry
storage. The registration declares only Accessibility permission. Spotter itself performs no network
request in this flow; after the verified Return event, ChatGPT sends through the user's account.

## Verification

`ChatGPTLauncherTypes.swift` is Foundation-only and pure. Its standalone harness verifies Unicode,
reserved-character and multiline deep-link round trips, outer-whitespace handling, line-ending
normalization and rejection of mismatched drafts without launching ChatGPT or synthesizing input.
