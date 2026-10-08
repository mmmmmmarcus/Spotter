# Spotter reply Markdown

Pinned CommonMark/GFM parsing with markdown-it, task-list and footnote plugins; syntax highlighting
with highlight.js; local formulas with KaTeX; local diagrams with Mermaid. The WebKit host never
loads a CDN. Runtime resources and their licenses are checked in under
`Spotter/Resources/AIChatMarkdown` so building Spotter requires neither Node nor npm.

```sh
npm ci --ignore-scripts
npm test
npm run build
```

Keep `package-lock.json` and generated resources together. The KaTeX override keeps Mermaid's math
renderer on the same patched version as the reply renderer. `build.mjs` collects dependency license
texts; `renderer.js` also retains bundled legal notices.

Reference behavior: https://github.com/openai/codex/blob/main/codex-rs/tui/src/markdown_render.rs
and https://learn.chatgpt.com/docs/non-interactive-mode (inspected 2026-10-09).

Raw HTML is escaped. Images are explicit links, not automatically fetched embeds. Mermaid uses strict
mode and KaTeX has trust disabled. Local file links are normalized and opened by the native host.
The native `ai-markdown` test loads the checked-in document under its actual CSP and tests rendering,
link/copy messages, streaming and width-dependent height without opening a visible window.
