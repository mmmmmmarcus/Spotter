# Tinycast extension runtime attribution

The Raycast compatibility implementation in `Spotter/Plugins/RaycastExtensions`, its render theme
in `Spotter/Core/Theme+Raycast.swift`, the JavaScript runtime under `scripts/raycast-runtime`, and
its standalone tests are adapted from [Tinycast](https://github.com/abue-ammar/tinycast), commit
`71279c8de18fe77c56aa1cfaaeb68bf07748bbdd` (retrieved 2026-10-08).

Copyright remains with Tinycast's contributors. These sources are distributed under GNU AGPL v3,
the same license as Spotter; the upstream license is included as `Tinycast-LICENSE.txt`.
Spotter changes provide AppCore ownership, native plugin registration, launcher and settings
integration, namespaced storage and artwork, and shared palette keyboard/navigation integration.
The generated JavaScript is built from the included runtime sources; do not edit it by hand.

The embedded runtime includes React and react-reconciler (MIT). Their license accompanies the
runtime in the application resources. No Raycast extension package is shipped with Spotter;
installed extensions retain their individual authors and licenses.

## Palette integration audit (2026-10-08)

Re-cloned upstream and compared against commit `71279c8de18fe77c56aa1cfaaeb68bf07748bbdd`.
All files under `scripts/raycast-runtime/src` are byte-for-byte identical to upstream's
`Scripts/raycast-runtime/src`. The Swift JavaScriptCore runtime differs only in its queue label;
the host bridge retains Spotter branding and its accessibility helper name.

The missing palette behavior was ported from upstream `ExtensionCommandScreen`: forms hide
launcher search, multiline fields retain vertical keys, rowless Detail/Form screens retain
primary/actions commands, actual primary-action titles appear in the footer, and a submenu
opens before a leaf can execute. `CommandArgumentsRow`, `ExtensionActionsPanel`, and
`ExtensionActionsMenu` now come from upstream, with Spotter metrics, theme, and palette-state
names. Password arguments additionally use a secure field. Arguments stay inside the palette;
requested extension settings reveal the corresponding extension. Command-specific artwork and
extension-name/keyword launcher search are preserved.

Host adaptations remain deliberate: AppCore and PluginRegistry own lifecycle, third-party-code
consent gates installs/runs, application-support paths use Spotter's bundle identifier, source
installs retain atomic staging, settings use Spotter's settings shell, and search accessory
selection uses a native header picker. The action panel's search text mirrors the palette's
input-freeze channel instead of taking first responder. This is an upstream runtime integration,
not a claim that every Raycast API or every third-party extension is supported by Tinycast.

The historical baseline can be compared with
`scripts/audit-tinycast-runtime.sh /absolute/path/to/tinycast`; intentional later ports now produce
differences, so this is a baseline diff, not a current byte-parity gate.
Behavioral verification uses `scripts/test-raycast.sh`, `scripts/test-raycast-models.sh`,
and `node scripts/raycast-runtime/fixtures.mjs`; the form harness also pins the host-facing
rowless actions, form focus/navigation, and submenu-primary behavior.

## Selective compatibility audit (2026-10-29)

Reviewed upstream through `37e6043f3f550febb64bdb3cff3ac29a30caad5a`. This is a selective port of
the OAuth/API and shortcut-retention fixes, not a replacement of Spotter's host or a claim of full
parity with that revision.

| Upstream change | Spotter integration | Verification |
| --- | --- | --- |
| [#1679 OAuth state](https://github.com/abue-ammar/tinycast/commit/980f7ac1319580d503c068ad6da6a363483df5fb) | Derive expected state from the outgoing URL, including overrides, strings and custom URL objects; native validation requires exactly one matching state across query and fragment. Web retains Spotter's existing JSON envelope and `tinycast` relay scheme; direct methods use a nonce. Client metadata redirects use their registered URI and default client metadata document. | `oauth-fixtures.mjs` checks request generation and the bridge contract. `ext-test.swift` checks missing, stale, repeated and encoded callback state, code/token presence, provider errors and all registered schemes. |
| [#1679 API 2.8.2](https://github.com/abue-ammar/tinycast/commit/980f7ac1319580d503c068ad6da6a363483df5fb) | Update the locked API dependency and regenerate enums/runtime. Add `Icon.Quicklink`; `AI.experimental_decide` and `AI.refreshModels` report unsupported API errors, as upstream does. | JavaScript fixtures check the actual exported members and errors. The existing native `quicklink` symbol mapping is retained. |
| [#1626 closed-screen retention](https://github.com/abue-ammar/tinycast/commit/c875fe19e97232a93e624e1f75660ebf52965992) | No source transplant: Spotter has no `ExtensionShortcutKeys` closure capturing a command screen. `PaletteWindowController` calls `ExtensionCoordinator.handleKey`, which resolves the current screen per event. | Source inspection of the event route; native runtime fixtures check timer shutdown and fresh reruns. Keep-awake tests separately pin intentional detached Coffee task survival and cancellation. These checks do not measure SwiftUI screen allocations. |

Preserved Spotter behavior includes AppCore ownership, consent, native OAuth callback delivery,
bundle-scoped Keychain tokens and expiry timestamps, fragment/implicit token callbacks, palette focus
and menus, and owned detached keep-awake tasks. Callback fixtures use local synthetic URLs; they do
not establish successful signed-in operations against a third-party OAuth provider.
