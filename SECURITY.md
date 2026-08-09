# Security Policy

## Reporting a Vulnerability

Report privately through GitHub: **Security** tab → **Report a vulnerability**.

Include your macOS version, the Spotter version and channel, reproduction steps, and the impact.
Please don't disclose publicly until it's fixed.

We'll respond as quickly as we can and keep you posted.

## Supported Versions

Current stable and beta only. Install the newest DMG from
[GitHub Releases](https://github.com/mmmmmmarcus/Spotter/releases) or use **Settings → General →
Check for Updates** before reporting.

## Scope

Of particular interest:

- **Accessibility (TCC)** — anything that widens what the paste grant enables.
- **Clipboard history** — text and images cached on disk; unintended exposure or capture.
- **Network** — Spotter is offline by default and every networked feature is consent-gated. A path
  that reaches the network without consent, or survives consent being withdrawn, is high severity.
- **Plugins** — plugins are signed native code compiled into Spotter. Any path that runtime-loads
  unsigned plugin code, scripts or bundles violates the security model.
- **Process control** — Kill Process must never target PID 0/1 or Spotter itself, and destructive
  actions must remain explicit and confirmation-gated by default.
- **Image writes** — replacing source files must require confirmation; temporary image output stays
  inside the bundle-identifier-scoped cache directory.
- **Automation** — Apple Events are sent only after a user invokes the relevant Finder or System
  command. No background automation is allowed.
- **Hotkeys** — the in-house hotkey stack and the Input Monitoring grant.
- **Signing and distribution** — the GitHub Release DMG, updater zip and in-app verification chain.

Local Debug builds are intentionally self-signed and are out of scope. Public releases are expected
to carry the documented Developer ID signature and Apple notarization ticket; report any published
artifact that does not. Anything needing existing code execution or admin rights is also out of
scope.
