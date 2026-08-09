import { site } from "../data/site";
import { GitHubLogo, Logo } from "./ui/icon";
import { MetaStrip } from "./ui/meta-strip";

export function Footer() {
  const repoPath = site.repo.replace("https://", "");

  return (
    <footer className="border-t border-border/50">
      <div className="container-page flex flex-col items-center gap-6 py-14 text-center">
        <a
          href="#top"
          className="flex items-center gap-1 text-body font-medium text-white"
        >
          <Logo size={24} />
          {site.name}
        </a>

        <div className="flex flex-col items-center gap-2">
          <MetaStrip />
          <p className="font-mono text-caption text-smoke">
            Made for people who like their Mac fast
          </p>
        </div>

        <div className="flex flex-wrap items-center justify-center gap-x-6 gap-y-3">
          <a
            href={site.repo}
            target="_blank"
            rel="noreferrer"
            className="flex items-center gap-2 text-small text-ash transition-colors hover:text-white"
          >
            <GitHubLogo size={16} />
            {repoPath}
          </a>
        </div>
      </div>
    </footer>
  );
}
