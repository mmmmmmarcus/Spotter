#!/bin/bash
# Points `gh` at this project's own GitHub identity instead of whatever account is signed in globally.
#
# Spotter lives under an account that differs from the one usually signed into `gh` on this Mac, and
# publishing reads the repository's Actions secrets — so a globally signed-in reader gets a 403
# halfway through a release.
#
# GH_CONFIG_DIR alone is NOT enough, and finding that out cost two failed releases: `gh auth login`
# records the *username* in the config directory but stores the token in one shared Keychain entry
# per host (`gh:github.com`, no account), so the next login anywhere overwrites it and both scopes
# end up on the same token. A token file is the only isolation that actually holds.
#
# Set up once, by the user, never by tooling:
#     1. Create a token at https://github.com/settings/tokens with the `repo` scope, on the account
#        that owns the repository. Reading Actions secrets needs admin on it.
#     2. printf '%s' <token> > ~/.config/gh-spotter/token && chmod 600 ~/.config/gh-spotter/token
#
# Sourcing is a no-op until that file exists, so a fresh clone keeps using the global login.

SPOTTER_GH_CONFIG_DIR="${SPOTTER_GH_CONFIG_DIR:-$HOME/.config/gh-spotter}"

if [ -r "$SPOTTER_GH_CONFIG_DIR/token" ]; then
    # Wins over the Keychain, so a login elsewhere can no longer redirect this project's releases.
    GH_TOKEN="$(cat "$SPOTTER_GH_CONFIG_DIR/token")"
    export GH_TOKEN
elif [ -d "$SPOTTER_GH_CONFIG_DIR" ]; then
    export GH_CONFIG_DIR="$SPOTTER_GH_CONFIG_DIR"
fi
