# 1Password

A launcher front end for the 1Password CLI (`op`), supporting 1Password 8 with the desktop-app
integration. Search every item from the palette, then open it in 1Password or a browser, copy or
paste its username, password or one-time password, and generate fresh passwords — without Spotter
ever storing a secret.

## Interaction model

Palette-first, following the Kill Process reference: one `PluginPaletteScreenRegistration` renders
the item list through the shared `PluginPaletteList`. There is no plugin window.

- **Search 1Password** (`command:1password`, bindable) opens the screen. Rows show the item title,
  the username (or category label) as subtitle, a category SF Symbol, a star for favorites and the
  vault name as an accessory. Favorites sort first, then title.
- **↵** runs the configured primary action (default *View Item*); categories that don't support the
  configured action fall back to *View Item* — a secure note can't paste a password. **⌘↵** copies
  the password when the category has one.
- **View Item** opens the item *inside the palette*: one row per non-empty field in 1Password's own
  order (an OTP field keeps its row even when the JSON holds no code), then the item's websites.
  Concealed fields render masked with a ⌘K *Reveal*/*Conceal* toggle scoped to the open view. ↵ on
  a field copies it concealed; ⌘K adds Paste, Open in 1Password and Back. A website row's ↵ opens
  the browser. The search field filters fields by name. **Esc and the header chevron step back to
  the item list first** (via the screen's `handleBack` hook) — only from the list do they leave the
  screen. Item rows lead with a colored category icon tile (`PluginPaletteIcon.tintedSymbol`),
  1Password-adjacent colors mapped per `op` category. Copying a one-time password from the open item
  view delivers the code already fetched with the item whenever its 30-second TOTP window still
  holds (`OnePasswordOTP.codeStillCurrent`, harness-covered) — instant instead of a second `op`
  round trip — and otherwise re-fetches through `--otp` so an expired code is never
  delivered.
- **The view renders instantly.** The full `op item get` costs seconds (the desktop app charges per
  concealed value), so the view opens immediately with provisional rows built from list metadata —
  username, a masked password, the website — and the full field set replaces them when the fetch
  lands. Acting on a provisional row is never blocked: the username and website are already in
  hand, and the password takes the direct `op read` path.
- **⌘K** lists every available action for the row: Open in 1Password, Open in Browser, Copy/Paste
  Username, Copy/Paste Password, Copy/Paste One-Time Password — mirroring the 1Password 8 category
  rules (logins offer everything, passwords drop the username actions, all other categories are
  open-only) — plus Refresh Items and 1Password Settings.
- **Generate Password** (`command:1password-generate-password`, hidden by default, bindable) copies
  a fresh password using the configured length/digits/symbols recipe via a `--dry-run` item create,
  so nothing is saved to the vault.

With no `op` binary the screen shows one install-guidance row (its action opens 1Password's CLI
install guide); Settings shows a callout and a path-override field, Mole-style. A locked session
renders an *Unlock 1Password* row whose action re-runs the list read — that is what makes the
1Password app raise its own authorization prompt.

## Architecture

```text
Spotter/Plugins/OnePassword/
├── OnePasswordPlugin.swift         # registration, palette rows, AppCore actions
├── OnePasswordTypes.swift          # pure: JSON parsing, argv builders, action rules (harnessed)
├── OnePasswordProcessRunner.swift  # one `op` process off-main, stdout/stderr kept separate,
│                                   # stdin the shared session TTY
├── OnePasswordManager.swift        # AppCore-owned state: binary, item cache, reveals, clipboard clear
└── OnePasswordSettingsView.swift
```

- `OnePasswordTypes.swift` stays Foundation-only and pure; `Tools/onepassword-test.swift` compiles
  it standalone and never executes `op`.
- Every `op` runs with one app-lifetime pseudo-terminal as stdin. The desktop app scopes CLI
  authorization to a terminal session, which `op` derives from the TTY it is attached to — with no
  TTY each invocation read as a brand-new session and 1Password re-prompted on every copy. One
  shared PTY makes all of Spotter's calls one session: authorize once, then only 1Password's own
  inactivity and 12-hour caps apply. Only stdin is the PTY; stdout and stderr stay captured pipes
  (with `NO_COLOR` set so TTY-colored diagnostics can't leak ANSI codes into error text).
- `OnePasswordProcessRunner` checks the real termination status and keeps **stdout and stderr
  separate**: stdout may be a secret and is returned verbatim; stderr is only distilled into an
  error message (log prefixes stripped) and classified as locked-vs-failed. Secrets never appear in
  argv, `AppLog`, or any error path.
- `OnePasswordManager` locates `op` (Homebrew paths, then a Settings override under
  `one-password.cli-path`), loads the item list on screen open with a session-long in-memory cache
  (stale-while-revalidate; a failed refresh keeps the stale list), resolves the account uuid lazily
  for `onepassword://view-item/` deep links, and owns the delayed clipboard clear.
- **An in-flight list read survives the palette hiding, and must keep doing so.** The palette
  dismisses itself the moment it loses key status — which is exactly what 1Password's authorization
  window causes — so closing the screen never cancels the running `op` (cancelling would kill the
  very request being authorized), and a reopen joins the in-flight read instead of restarting it
  (a restart would dismiss the prompt and re-raise it). The finished read fills the session cache
  for the next open; only disabling the plugin interrupts `op`.

## What runs when

Everything is `op`, executed only on an explicit user action:

- Screen open → `op item list --format=json` (titles, categories, vaults, usernames, URLs —
  **no secrets**), then once per session `op account get --format=json` for the deep-link account id.
  Deliberately **without `--long`**: the plain listing already carries everything Spotter renders,
  and the per-item field detail `--long` adds pushed a ~1000-item vault past `op`'s internal
  30-second desktop-app timeout. A timeout gets one automatic retry (a cold `op` daemon can trip it
  once, then answer from its cache in seconds); a persistent failure renders as a *Try Again* row.
- View Item → `op item get <item> --vault <vault> --format=json`. This response includes the item's
  concealed field values: they are held **in memory only while the view is open** — rendered masked
  until explicitly revealed — and dropped on Back, on opening another item, and on disable.
- Copy/paste username or password → `op read op://<vault>/<item>/<field>`.
- Copy/paste one-time password → `op item get <item> --vault <vault> --otp`.
- Generate Password → `op item create --dry-run --category Password --generate-password=… --format=json`.

## Security posture

- **Consent** (owner decision, Aug 2026): the plugin ships enabled but is inert until the user has
  installed `op` and enabled the CLI integration in 1Password — and every `op` call is authorized by
  1Password 8's own biometric/authorization prompt, the same gate as running `op` in a terminal.
  Spotter adds no network path of its own; the CLI talks to 1Password exactly as it does for the
  user. Do not add a second consent dialog, and do not copy this shape for a feature whose network
  access is Spotter's own.
- **Nothing persists.** The item list lives in memory for the session and is dropped on disable;
  no index, no cache file, no secret is ever written to disk. Only preferences (CLI path override,
  primary action, clipboard-clear switch, password recipe) persist, and those sync through
  `SettingsBackup.PluginPrefs.OnePassword`.
- **Secrets pass through the pasteboard concealed.** `Paster.copyConcealedString` /
  `pasteConcealedString` stamp both Spotter's internal marker and `org.nspasteboard.ConcealedType`,
  so Spotter's own history and other clipboard managers skip them. A copied or pasted secret is
  cleared after 90 seconds (1Password's own default) unless something replaced it; the clear is
  changeCount-guarded so it never wipes a later copy, and it stays armed even if the plugin is
  disabled meanwhile. The switch lives in Settings (`one-password.clear-clipboard`, default on).
- Paste targets the recorded previous app through the shared `Paster` ⌘V path, so it requires the
  Accessibility permission the plugin declares.
