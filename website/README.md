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
