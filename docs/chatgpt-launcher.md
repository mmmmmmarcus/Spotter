# Send to ChatGPT

Send to ChatGPT is a native, enabled-by-default plugin that hands one prompt from Spotter to a new
Chat session in the current ChatGPT desktop app for macOS. It is separate from Spotter's built-in AI Chat:
it uses the user's signed-in ChatGPT app and does not use the OpenRouter key.

## Interaction

`Send to ChatGPT` is a launcher command and an optional global shortcut. It opens a registered
plugin palette screen using the shared Spotter search field and `PluginPaletteList`. The query
becomes one selectable prompt row; pressing Return starts the handoff and dismisses Spotter without
restoring the previously focused app.

The plugin first activates ChatGPT and invokes its Switch to Chat shortcut (`Control-1`). Only after
the Chat composer is verified does Spotter open the official `codex://new?prompt=…` deep link, which
creates a new local session and preloads the composer. This explicit switch prevents the generic deep
link from inheriting a currently visible Work or Codex mode. The prompt is encoded with
`URLComponents`; Spotter does not put it on the clipboard, store it, or include it in diagnostics.

## Safe submission

The deep link deliberately performs only the documented prefill. Automatic submission is a separate,
Accessibility-gated step:

1. Spotter resolves the registered `codex` handler and requires the official ChatGPT bundle
   identifier, then activates that application without opening the prompt.
2. `ChatGPTLauncherCoordinator` posts `Control-1` to the ChatGPT process and opts its Chromium
   accessibility tree in for the duration of the attempt.
3. The automation identifies the composer's two-button Chat/Work mode group structurally and requires
   the first, Chat button to be the sole selected option. It does not depend on localized labels.
4. Spotter opens the deep link only after that check passes. Before sending, it again requires the
   Chat selection plus a focused editable control whose full value matches the prepared prompt.
5. Only that doubly verified state receives a Return key event targeted to the ChatGPT process.

The mode switch is bounded to five seconds and the final draft check to ten seconds. Both are cancelled
when the plugin is disabled or a newer handoff starts. If Chat mode cannot be confirmed, Spotter never
opens the prompt. If the deep-linked composer cannot be jointly verified as Chat with the exact draft,
Spotter posts no key event and reports that the draft was not sent. This fail-closed behavior also
covers a customized or removed Switch to Chat shortcut.

## Ownership and permissions

`AppCore` owns the single `ChatGPTLauncherCoordinator`; it retains only the current cancellable task
and has no persisted state. Plugin enablement and the optional shortcut use the standard registry
storage. The registration declares only Accessibility permission. Spotter itself performs no network
request in this flow; after the verified Return event, ChatGPT sends through the user's account.

## Verification

`ChatGPTLauncherTypes.swift` is Foundation-only and pure. Its standalone harness verifies Unicode,
reserved-character and multiline deep-link round trips, outer-whitespace handling, line-ending
normalization, rejection of mismatched drafts, and the exact Chat-versus-Work selection shape without
launching ChatGPT or synthesizing input.
