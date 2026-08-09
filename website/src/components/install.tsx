import { ArrowUpRight, Download } from "lucide-react";
import { site } from "../data/site";
import { Button } from "./ui/button";
import { Reveal } from "./ui/reveal";
import { Section } from "./ui/section";

export function Install() {
  return (
    <Section
      id="install"
      eyebrow="Get it"
      title="Download the signed DMG."
      intro="Every public release is signed with Developer ID, notarized by Apple, and ready to drag into Applications."
    >
      <Reveal className="mx-auto max-w-3xl">
        <div className="rounded-2xl border border-border bg-white/5 p-8 text-center">
          <ol className="mx-auto mb-8 max-w-xl space-y-3 text-left text-body text-ash">
            <li>1. Download the latest Spotter DMG from GitHub Releases.</li>
            <li>2. Open it and drag Spotter.app to Applications.</li>
            <li>3. Launch Spotter and grant permissions only when a feature asks.</li>
          </ol>

          <div className="flex flex-wrap justify-center gap-3">
            <Button
              href={`${site.repo}/releases/latest`}
              target="_blank"
              rel="noreferrer"
            >
              <Download size={16} />
              Download latest release
            </Button>
            <Button
              href={`${site.repo}/releases`}
              variant="ghost"
              target="_blank"
              rel="noreferrer"
            >
              <ArrowUpRight size={16} />
              All releases and betas
            </Button>
          </div>

          <p className="mt-6 font-mono text-caption text-smoke">
            macOS 26+ · Developer ID signed · Apple notarized
          </p>
        </div>
      </Reveal>
    </Section>
  );
}
