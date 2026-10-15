#!/usr/bin/env python3
"""Generate public static feeds from authenticated, published GitHub release metadata."""
import argparse
import json
import pathlib
import re
import subprocess

REPOSITORY = "mmmmmmarcus/Spotter"
BASE = f"https://github.com/{REPOSITORY}/releases"
VERSION = re.compile(r"^v(\d+)\.(\d+)\.(\d+)(?:-beta\.(\d+))?$")


def version_key(release):
    match = VERSION.fullmatch(release.get("tag_name", ""))
    if not match:
        return None
    major, minor, patch, beta = match.groups()
    if bool(beta) != bool(release.get("prerelease")):
        raise ValueError("Tag and release channel disagree")
    return (int(major), int(minor), int(patch), beta is None, int(beta or 0))


def manifests(releases, expected=None):
    feeds = {}
    for channel in ("stable", "beta"):
        candidates = [r for r in releases if not r.get("draft")
                      and bool(r.get("prerelease")) == (channel == "beta")
                      and version_key(r) is not None]
        candidates.sort(key=version_key, reverse=True)
        entries = []
        for release in candidates[:10]:
            tag = release["tag_name"]
            version = tag[1:]
            assets = release.get("assets", [])
            urls = {}
            for suffix in ("zip", "dmg"):
                name = f"Spotter-{version}.{suffix}"
                matches = [a for a in assets if a.get("name") == name and a.get("state") == "uploaded"]
                expected_url = f"{BASE}/download/{tag}/{name}"
                if len(matches) == 1 and matches[0].get("size", 0) > 0 and matches[0].get("browser_download_url") == expected_url:
                    urls[suffix] = expected_url
            # Never advertise a new version until its two installation artifacts exist.
            if len(urls) != 2:
                if not entries:
                    raise ValueError(f"Latest {channel} release {tag} has missing or invalid assets")
                continue
            if release.get("html_url") != f"{BASE}/tag/{tag}":
                raise ValueError(f"Unexpected release URL: {tag}")
            entries.append({"version": version, "releaseURL": release["html_url"],
                            "zipURL": urls["zip"], "dmgURL": urls["dmg"],
                            "releaseNotes": (release.get("body") or "").strip()})
        feeds[channel] = {"schemaVersion": 1, "channel": channel, "releases": entries}
    if not feeds["stable"]["releases"]:
        raise ValueError("No published stable release")
    if expected:
        match = VERSION.fullmatch(expected)
        if not match:
            raise ValueError("Invalid expected release tag")
        channel = "beta" if match.group(4) else "stable"
        if not any(r["version"] == expected[1:] for r in feeds[channel]["releases"]):
            raise ValueError(f"Expected published release {expected} is missing")
    return feeds


def github_json(endpoint):
    return json.loads(subprocess.check_output(["gh", "api", endpoint]))


def fetch_releases():
    releases = []
    # Fetch metadata only on the publishing machine; no credentials enter the public output.
    for page in range(1, 101):
        batch = github_json(f"repos/{REPOSITORY}/releases?per_page=100&page={page}")
        releases.extend(batch)
        if len(batch) < 100:
            break
    else:
        raise ValueError("Release catalog exceeds the bounded page limit")
    for channel in (False, True):
        candidates = [r for r in releases if not r.get("draft") and bool(r.get("prerelease")) == channel and version_key(r) is not None]
        for release in sorted(candidates, key=version_key, reverse=True)[:10]:
            # Dedicated asset metadata avoids the releases-list publication lag.
            release["assets"] = github_json(f"repos/{REPOSITORY}/releases/{int(release['id'])}/assets?per_page=100")
    return releases


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=pathlib.Path, help="Use a fixture instead of GitHub")
    parser.add_argument("--output", type=pathlib.Path, required=True)
    parser.add_argument("--expected", help="Fail unless the release just published is present")
    args = parser.parse_args()
    releases = json.loads(args.input.read_text()) if args.input else fetch_releases()
    feeds = manifests(releases, args.expected)
    args.output.mkdir(parents=True, exist_ok=True)
    for channel, feed in feeds.items():
        path = args.output / f"{channel}.json"
        path.write_text(json.dumps(feed, ensure_ascii=False, indent=2) + "\n")
        print(f"Generated {channel}: {len(feed['releases'])} releases")


if __name__ == "__main__":
    main()
