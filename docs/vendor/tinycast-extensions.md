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
