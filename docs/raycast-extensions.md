# Raycast extensions

Spotter hosts Raycast extensions using Tinycast's JavaScriptCore/React compatibility runtime,
adapted from commit `71279c8de18fe77c56aa1cfaaeb68bf07748bbdd`. The native adapter renders List,
Grid, Detail, Form, actions, toasts and menu-bar commands inside Spotter. This is execution of real
extension bundles, separate from the existing Raycast Snippets/Quicklinks importer.

## Use

1. Search **Raycast extension store** in the palette. Enable the compatibility runtime there if needed.
2. Type in the palette search field to search Raycast Store, then press Return to install. Paste a GitHub extension folder URL for source installation. Clear the query for local/Raycast import, updates and cleanup. Real installation stages appear in the palette, and Cancel or closing the palette cancels pending work.
3. Each installed extension has its own Settings sidebar destination under **Raycast Extension**. Configure preferences there and use Run, search its command in the main palette, or
   assign a shortcut. Search matches command titles, extension names and declared keywords; rows show
   the owning extension. Commands with arguments prompt before execution.

Store and built-folder installs need no Node runtime. GitHub source installs require a local Node.js
and supported package manager, and execute third-party build scripts. The package manager and extra
executable search paths are configurable. Updates are checked and installed on request. An update is
staged before replacing the existing extension. Uninstall removes its local data; cleanup only removes
orphaned extension data and installation workspaces.

## Compatibility and boundaries

The vendored runtime includes React reconciliation, Raycast component/API shims, preferences,
local storage/cache, clipboard/selection access, navigation, OAuth/PKCE, fetch, WebSocket, DNS,
filesystem and child-process bridges, menu-bar commands and background refresh. macOS permissions
still apply. Only enable extensions you trust: they execute inside Spotter's process and can access
files, start processes and reach their own network services.

This aligns with the pinned Tinycast implementation, not every API in Raycast. Raycast proprietary
AI, BrowserExtension and WindowManagement APIs are not implemented; unsupported calls report
errors. Native Node addons and arbitrary Node networking modules are not a full Node.js environment.
An extension's own service, credentials and macOS helper requirements still apply.

Spotter retains its own palette, settings and shortcut UI. Native Actions menus preserve sections and
submenus; the shared searchable action picker flattens them with contextual titles. URL schemes
`spotter`, `raycast`, `com.raycast` and `raycastinternal` enter the extension coordinator. If another
installed app owns a scheme, macOS may deliver its links there instead. Spotter does not forcibly
change the system's default URL handler.

## Ownership and persistence

AppCore solely owns ExtensionManager/ExtensionCoordinator. Enablement defaults off and is not part
of backup/sync. Preferences, installs and data use the app bundle's Application Support directory;
OAuth secrets use the bundle-scoped keychain service. Dev and stable share Spotter's bundle identity.
The native built-in registry remains compile-time; the Raycast adapter supplies dynamic commands
and shortcuts. Closing a view releases its runtime unless a host-requested hide or OAuth flow is in
progress. Disabling stops runtimes and background commands.

## Validation

- `scripts/test-raycast.sh`: real Swift/JavaScriptCore bridges, render trees, network fixtures and lifecycle.
- `scripts/test-raycast-models.sh`: manifest/store parsing, catalog replacement, cleanup, refresh,
  metadata, versions, forms, keyboard behavior, image sizing and search accessories.
- `node scripts/raycast-runtime/fixtures.mjs`: JavaScript compatibility fixtures; install the locked
  development dependencies under `scripts/raycast-runtime` first.
- `scripts/test-raycast.sh /path/to/built-extension command-name`: real extension smoke test.
  Optional `EXT_TEST_ARGS='name=value'` and `EXT_TEST_RERUN=1` exercise arguments and a fresh context.

Color Shades was exercised from a real store bundle: List and an 11-item Grid render tree, with a
second fresh runtime execution. This is runtime validation, not a visual acceptance check or a claim
that every store extension works. See [third-party attribution](vendor/tinycast-extensions.md).

Slack (Momme) was installed and reinstalled through Spotter's store UI on October 8, 2026. All nine
commands were registered, and Open Channel launched the real bundle and opened Slack's workspace
sign-in page in the default browser. Workspace authorization and signed-in Slack operations remain
untested. The current installer reports completion in the palette; installed extensions have independent Settings pages.
The native selection modifier must be inside both extension environment injections; reversing that
order crashes SwiftUI before the command screen can render. While OAuth is pending, reopening the
extension screen explains that sign-in must be completed in the browser.


Global runtime consent, launcher visibility and source-build options live under General → Raycast
Extension. Installation controls and the combined installed-extension list have been removed from
Settings. Uninstall removes the dynamic sidebar destination. Command artwork is decoded as image
content through ExtensionIconCache, with assets-directory and extension-root resolution; the
launcher does not ask NSWorkspace for the image file’s generic document icon.
