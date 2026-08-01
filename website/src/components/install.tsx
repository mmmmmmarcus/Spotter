import { ArrowUpRight, Check, Copy, Terminal } from "lucide-react";
import { useState } from "react";
import { channels, quarantineCommand, site } from "../data/site";
import { cn } from "../lib/cn";
import { Button } from "./ui/button";
import { Reveal } from "./ui/reveal";
import { Section } from "./ui/section";

// A terminal-style command line with a copy button. The mono treatment signals
// "this is a command to run," and copy is the one action people want here.
function CopyCommand({ command }: { command: string }) {
  const [copied, setCopied] = useState(false);

  async function copy() {
    try {
      await navigator.clipboard.writeText(command);
      setCopied(true);
      setTimeout(() => setCopied(false), 1600);
    } catch {
      // Clipboard blocked (e.g. insecure context) — the text stays selectable.
    }
  }

  return (
    <div className="flex items-center gap-3 rounded-lg bg-obsidian px-4 py-3 shadow-key">
      <span className="shrink-0 select-none text-smoke">
        <Terminal size={16} />
      </span>
      <code className="min-w-0 flex-1 whitespace-pre-wrap wrap-break-word font-mono text-small text-white">
        {command}
      </code>
      <button
        type="button"
        onClick={copy}
        className="flex shrink-0 items-center gap-1.5 rounded-md px-2 py-1 font-mono text-caption text-ash transition-colors hover:bg-white/5 hover:text-white"
        aria-label={copied ? "Copied" : "Copy command"}
      >
        {copied ? <Check size={13} /> : <Copy size={13} />}
        {copied ? "Copied" : "Copy"}
      </button>
    </div>
  );
}

export function Install() {
  const [active, setActive] = useState(0);
  const channel = channels[active];

  return (
    <Section
      id="install"
      eyebrow="Get it"
      title="Install with Homebrew."
      intro="One command and you're running. Pick a channel — each installs as its own app, so a pre-release can live next to stable."
    >
      <Reveal className="mx-auto max-w-4xl">
        {/* Channel picker */}
        <div className="mb-3 inline-flex rounded-lg bg-white/5 p-1">
          {channels.map((c, i) => (
            <button
              key={c.id}
              type="button"
              onClick={() => setActive(i)}
              className={cn(
                "rounded-md px-4 py-1.5 text-small font-medium transition-colors",
                i === active
                  ? "bg-mist text-iron"
                  : "text-ash hover:text-white",
              )}
            >
              {c.label}
            </button>
          ))}
        </div>

        <div className="mb-3 font-mono text-caption text-smoke">
          <span className="rounded-md bg-graphite px-1.5 py-0.5 text-ash">
            {channel.note}
          </span>
        </div>

        <CopyCommand command={channel.command} />

        {/* The one manual step, stated plainly rather than hidden. */}
        <div className="mt-8 rounded-2xl border border-border p-4 sm:p-6">
          <h3 className="text-body-lg font-medium">
            One-time: clear the quarantine flag
          </h3>
          <p className="mt-2 text-body text-ash">
            Spotter isn't notarized — there's no paid Developer ID behind it —
            so macOS quarantines it on first launch. Run this once to let it
            open:
          </p>
          <div className="mt-4">
            <CopyCommand command={quarantineCommand} />
          </div>
        </div>

        <div className="mt-8 flex flex-wrap justify-center gap-3">
          <Button
            href={`${site.repo}/releases`}
            variant="ghost"
            target="_blank"
            rel="noreferrer"
          >
            <ArrowUpRight size={16} />
            Or grab the .dmg from Releases
          </Button>
        </div>
      </Reveal>
    </Section>
  );
}
