# Spotter website

Marketing site for [Spotter](../), built with React + Vite + Tailwind CSS.

## Develop

```sh
npm install
npm run dev      # local dev server with HMR
```

## Scripts

- `npm run dev` — start the dev server
- `npm run build` — type-check and build to `dist/`
- `npm run preview` — serve the production build locally
- `npm run lint` — run oxlint
- `npm run format` — format with Prettier

## Deploy

Pushes to `main` that touch `website/**` are built and published to GitHub Pages
by [`.github/workflows/website.yml`](../.github/workflows/website.yml) —
live at <https://mmmmmmarcus.github.io/Spotter/>.

The site is served from the `/Spotter/` subpath, set via `base` in
[`vite.config.ts`](vite.config.ts).

## Update metadata

The Pages build runs `scripts/generate-update-feed.py` with the workflow's GitHub token before
building Vite. It produces `/Spotter/updates/stable.json` and `beta.json` from published GitHub
Releases, including release notes and complete installation links. Both the app and the site's
version label read these static files; visitors never call the GitHub API. App release workflows
invoke this same deployment after publishing packages. Public feed bytes are checked after deploy.
For a local preview with real metadata, source `scripts/gh-env.sh` from the repository root and run
`python3 scripts/generate-update-feed.py --output website/public/updates` before building the site.
