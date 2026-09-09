#!/bin/bash
# Points `gh` at this project's own login instead of whatever account is signed in globally.
#
# Spotter lives under an org account that differs from the one signed into `gh` on this Mac, and
# publishing needs to read the repository's Actions secrets — so a globally signed-in reader gets a
# 403 halfway through a release. `gh` has no per-repository account (this Mac's 2.35 has no
# `auth switch` at all), but it does honour GH_CONFIG_DIR, so the project keeps a config dir of its
# own and every script that talks to GitHub sources this file first.
#
# The directory is deliberately OUTSIDE the repository: it holds an OAuth token, and a token inside
# a working tree is one `git add -A` away from being published.
#
# Set up once, by the user, never by tooling:
#     source scripts/gh-env.sh && gh auth login
#
# Sourcing is a no-op until that directory exists, so a fresh clone keeps using the global login.

SPOTTER_GH_CONFIG_DIR="${SPOTTER_GH_CONFIG_DIR:-$HOME/.config/gh-spotter}"
if [ -d "$SPOTTER_GH_CONFIG_DIR" ]; then
    export GH_CONFIG_DIR="$SPOTTER_GH_CONFIG_DIR"
fi
