// Spotter vs Raycast, in one honest table. `true`/`false` render as a check or
// a muted cross; a string renders as-is. The essentials come first (both apps do
// them), then the differences that actually decide it. Every value here is
// sourced — the native/memory rows come from Raycast's own engineering blog
// (see `compareSource`), so nothing is a claim we can't back up.

export type Cell = boolean | string;

export type CompareRow = {
  label: string;
  spotter: Cell;
  raycast: Cell;
  // `sourced` rows get a † marker tying them to the footnote citation.
  sourced?: boolean;
};

export const compareRows: CompareRow[] = [
  { label: "App launcher", spotter: true, raycast: true },
  { label: "Clipboard history", spotter: true, raycast: true },
  { label: "Calculator, unit & currency conversion", spotter: true, raycast: true },
  { label: "Emoji & symbol picker", spotter: true, raycast: true },
  { label: "Process, text case, image & recording tools", spotter: true, raycast: true },
  { label: "Global & per-app hotkeys", spotter: true, raycast: true },
  { label: "Hyper key", spotter: true, raycast: true },
  {
    label: "Unlimited clipboard history",
    spotter: true,
    raycast: "Pro only",
  },
  {
    label: "Built with",
    spotter: "Native SwiftUI + AppKit",
    raycast: "React WebView + Node + Rust",
    sourced: true,
  },
  {
    label: "Memory footprint",
    spotter: "<100 MB",
    raycast: "500 MB+",
    sourced: true,
  },
  { label: "On disk", spotter: "<3 MB", raycast: "Hundreds of MB" },
  { label: "Price", spotter: "Free forever", raycast: "Freemium (Pro)" },
  { label: "Open source", spotter: true, raycast: false },
  { label: "Account required", spotter: false, raycast: true },
  { label: "Telemetry", spotter: "None", raycast: "Yes" },
];

// The one external claim on the page — Raycast's stack and memory numbers come
// straight from their own write-up, linked so anyone can check.
export const compareSource = {
  label: "Raycast's own engineering blog",
  href: "https://www.raycast.com/blog/a-technical-deep-dive-into-the-new-raycast",
} as const;
