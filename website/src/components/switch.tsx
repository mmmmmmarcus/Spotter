import { Check } from "lucide-react";
import { migration } from "../data/migration";
import { Button } from "./ui/button";
import { AppleLogo } from "./ui/icon";
import { Reveal } from "./ui/reveal";

// "Switch from Raycast" — a two-column band: the three-step import story on the
// left, the real import screen framed like the hero shot on the right. Left copy
// is intentionally left-aligned, so it skips the centered <Section> header.
export function Switch() {
  return (
    <section id="switch" className="container-page py-16 md:py-24">
      <div className="grid items-center gap-10 lg:grid-cols-2 lg:gap-16">
        <Reveal className="order-2 lg:order-1">
          <p className="mb-4 font-mono text-eyebrow uppercase text-violet-bright">
            {migration.eyebrow}
          </p>
          <h2 className="text-heading">{migration.title}</h2>
          <p className="mt-4 text-body-lg text-ash">{migration.intro}</p>

          {/* The three-step flow. */}
          <ol className="mt-8 space-y-4">
            {migration.steps.map((step, i) => (
              <li key={step.title} className="flex gap-4">
                <span className="mt-0.5 flex size-6 shrink-0 items-center justify-center rounded-full bg-violet/15 font-mono text-caption font-medium text-violet-bright">
                  {i + 1}
                </span>
                <div>
                  <h3 className="text-body-lg font-medium">{step.title}</h3>
                  <p className="mt-1 text-body text-ash">{step.body}</p>
                </div>
              </li>
            ))}
          </ol>

          {/* What actually carries over — mirrors the app's import options. */}
          <div className="mt-8">
            <p className="mb-3 font-mono text-caption text-smoke">
              Comes across
            </p>
            <ul className="flex flex-wrap gap-2">
              {migration.transfers.map((item) => (
                <li
                  key={item}
                  className="inline-flex items-center gap-1.5 rounded-lg bg-white/5 px-2.5 py-1.5 text-small text-ash shadow-keycap"
                >
                  <Check size={13} strokeWidth={2.4} className="text-violet-bright" />
                  {item}
                </li>
              ))}
            </ul>
          </div>

          <div className="mt-9">
            <Button href="#install" className="gap-1">
              <AppleLogo size={20} />
              Make the switch
            </Button>
          </div>
        </Reveal>

        <Reveal delay={80} className="order-1 lg:order-2">
          <figure className="w-full overflow-hidden rounded-2xl shadow-window">
            <img
              src={`${import.meta.env.BASE_URL}import.png`}
              width={1800}
              height={1192}
              alt="Spotter's Import from Raycast screen, with Shortcuts, Favorites, Emoji skin tone, Launch at login, Menu-bar icon, and Clipboard history all selected to import."
              className="block h-auto w-full"
              loading="lazy"
              decoding="async"
            />
          </figure>
        </Reveal>
      </div>
    </section>
  );
}
