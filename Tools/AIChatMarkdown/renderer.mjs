import { renderMarkdown } from './parser.mjs';
import mermaid from 'mermaid';
const root = document.getElementById('reply');
let revision = 0;
let previousText = '';
let previousStyle = '';
const post = message => window.webkit?.messageHandlers?.markdown?.postMessage(message);
const measure = () => post({ kind: 'height', value: Math.ceil(root.getBoundingClientRect().height) });
new ResizeObserver(measure).observe(root);
window.spotterRender = async (text, style, streaming, reducedMotion, grammar = false) => {
  if (previousText === text && previousStyle === style && root.dataset.streaming === String(streaming) && root.dataset.grammar === String(grammar)) return;
  const current = ++revision;
  const changedStyle = previousStyle !== style;
  previousText = text; previousStyle = style;
  document.getElementById('theme').textContent = style;
  root.dataset.streaming = String(streaming);
  root.dataset.grammar = String(grammar);
  const oldHeight = root.getBoundingClientRect().height;
  const html = renderMarkdown(text, grammar);
  if (root.dataset.html !== html) { root.innerHTML = html; root.dataset.html = html; }
  if (streaming && !reducedMotion && root.getBoundingClientRect().height > oldHeight + 5) {
    const added = root.getBoundingClientRect().height - oldHeight;
    root.animate([{ clipPath: `inset(0 0 ${added}px 0)` }, { clipPath: 'inset(0 0 0 0)' }], { duration: 140, easing: 'ease-out' });
  }
  measure();
  if (streaming) return;
  mermaid.initialize({ startOnLoad: false, securityLevel: 'strict', suppressErrorRendering: true,
    theme: getComputedStyle(document.documentElement).colorScheme === 'dark' ? 'dark' : 'default',
    maxTextSize: 30000, maxEdges: 300, flowchart: { htmlLabels: false } });
  for (const element of root.querySelectorAll('.diagram')) {
    if (element.dataset.rendered && !changedStyle) continue;
    const source = element.dataset.source;
    if (!source || source.length > 30000) continue;
    try {
      const { svg } = await mermaid.render(`diagram-${current}-${Math.random().toString(36).slice(2)}`, source);
      if (current !== revision || !element.isConnected) return;
      element.innerHTML = svg;
      element.dataset.rendered = 'true';
      element.parentElement.querySelector('pre').hidden = true;
    } catch { element.textContent = ''; }
  }
  measure();
};
document.addEventListener('click', event => {
  const copy = event.target.closest('[data-copy]');
  if (copy) { post({ kind: 'copy', value: copy.closest('.code-block').querySelector('code').textContent }); return; }
  const link = event.target.closest('a');
  if (!link) return;
  event.preventDefault();
  const href = link.getAttribute('href');
  if (href?.startsWith('#')) {
    const target = document.getElementById(decodeURIComponent(href.slice(1)));
    if (target) post({ kind: 'scroll', value: target.getBoundingClientRect().top });
    return;
  }
  post({ kind: 'link', value: href });
});
post({ kind: 'ready' });
