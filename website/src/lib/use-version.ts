import { useEffect, useState } from "react";
import { site } from "../data/site";

const feedUrl = `${import.meta.env.BASE_URL}updates/stable.json`;

// Deduped across every hook consumer: fetch the tag at most once per page load.
let cached: string | null = null;
let inflight: Promise<string> | null = null;

async function fetchLatest(): Promise<string> {
  const res = await fetch(feedUrl);
  if (!res.ok) throw new Error(`Update feed HTTP ${res.status}`);
  const data: unknown = await res.json();
  if (!data || typeof data !== "object" || !("schemaVersion" in data) || data.schemaVersion !== 1 ||
      !("channel" in data) || data.channel !== "stable" || !("releases" in data) || !Array.isArray(data.releases)) {
    throw new Error("Invalid update feed");
  }
  const release = data.releases[0];
  const version = release && typeof release.version === "string" ? release.version : "";
  return /^\d+\.\d+\.\d+$/.test(version) ? `v${version}` : site.version;
}

/**
 * The latest published release tag (e.g. "v0.2.1"), falling back to the pinned
 * `site.version` while the request is in flight or if it fails (no releases,
 * offline, unavailable). Renders the fallback first, so there's no flash.
 */
export function useLatestVersion(): string {
  const [version, setVersion] = useState(cached ?? site.version);

  useEffect(() => {
    if (cached) {
      setVersion(cached);
      return;
    }
    let active = true;
    inflight ??= fetchLatest().then((v) => (cached = v));
    inflight.then((v) => active && setVersion(v)).catch(() => {});
    return () => {
      active = false;
    };
  }, []);

  return version;
}
