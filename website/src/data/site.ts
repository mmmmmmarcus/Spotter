// Single source of truth for links and metadata used across the page.

export const site = {
  name: "Spotter",
  tagline: "The essentials, without the bloat.",
  repo: "https://github.com/mmmmmmarcus/Spotter",
  version: "v1.5.5",
  platform: "macOS 26+",
  license: "AGPL-3.0",
  licenseUrl: "https://github.com/mmmmmmarcus/Spotter/blob/main/LICENSE",
} as const;

// The hero, in as few words as possible — headline plus one punchy line.
export const hero = {
  eyebrow: "Native macOS launcher",
  headline: "Everything on your Mac. One keystroke away.",
  sub: "A tiny, native launcher. No Electron. No account. No telemetry. No bullshit.",
} as const;

export const nav = [
  { label: "Gallery", href: "#gallery" },
  { label: "Features", href: "#features" },
  { label: "Compare", href: "#compare" },
  { label: "Why tiny", href: "#why" },
  { label: "Install", href: "#install" },
] as const;

// Headline numbers for the "why it's tiny" band. Kept honest, from the README.
export const stats = [
  { value: "<3", unit: "MB", label: "On disk" },
  { value: "<100", unit: "MB", label: "Memory" },
  { value: "0", unit: "", label: "Dependencies" },
  { value: "0", unit: "", label: "Telemetry" },
] as const;
