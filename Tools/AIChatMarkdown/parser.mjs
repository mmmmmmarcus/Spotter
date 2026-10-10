import MarkdownIt from 'markdown-it';
import taskLists from 'markdown-it-task-lists';
import footnote from 'markdown-it-footnote';
import hljs from 'highlight.js';
import katex from 'katex';

export const md = new MarkdownIt({ html: false, linkify: true, breaks: false, highlight(code, language) {
  if (language && hljs.getLanguage(language)) {
    try { return hljs.highlight(code, { language, ignoreIllegals: true }).value; } catch {}
  }
  return '';
}}).use(taskLists, { enabled: false }).use(footnote);
const escape = md.utils.escapeHtml;
md.validateLink = href => /^(https?:|mailto:|file:|\/|\.{1,2}\/|#)/i.test(href) || !/^[a-z][a-z0-9+.-]*:/i.test(href);
md.renderer.rules.image = (tokens, i) => {
  const token = tokens[i];
  const href = token.attrGet('src') || '';
  return `<a class="image-link" href="${escape(href)}">▧ ${escape(token.content || 'Open image')}</a>`;
};
const fence = md.renderer.rules.fence;
md.renderer.rules.fence = (tokens, i, options, env, self) => {
  const token = tokens[i];
  const language = token.info.trim().split(/\s/)[0];
  if (env?.grammar && language.toLowerCase() === 'json') {
    const grammar = renderGrammarJSON(token.content);
    if (grammar !== null) return grammar;
  }
  const code = fence(tokens, i, options, env, self);
  const diagram = language === 'mermaid' ? `<div class="diagram" data-source="${escape(token.content)}"></div>` : '';
  return `<section class="code-block"><header><span>${escape(language || 'Code')}</span><button type="button" data-copy>Copy</button></header>${diagram}${code}</section>`;
};
function math(source, displayMode) {
  try { return katex.renderToString(source, { displayMode, throwOnError: false, trust: false, strict: 'ignore', maxExpand: 500, maxSize: 20 }); }
  catch { return `<code>${escape(source)}</code>`; }
}
md.inline.ruler.before('escape', 'spotter_math', (state, silent) => {
  const start = state.pos;
  const open = state.src.startsWith('\\(', start) ? '\\(' : state.src[start] === '$' && state.src[start + 1] !== '$' ? '$' : null;
  if (!open) return false;
  const close = open === '$' ? '$' : '\\)';
  const contentStart = start + open.length;
  if (open === '$' && /\s/.test(state.src[contentStart] || '')) return false;
  let end = state.src.indexOf(close, contentStart);
  while (end >= 0 && state.src[end - 1] === '\\') end = state.src.indexOf(close, end + close.length);
  if (end < 0 || end === contentStart) return false;
  if (open === '$' && (/\s/.test(state.src[end - 1]) || /\d/.test(state.src[end + 1] || ''))) return false;
  if (!silent) { const token = state.push('spotter_math', '', 0); token.content = state.src.slice(contentStart, end); }
  state.pos = end + close.length;
  return true;
});
md.renderer.rules.spotter_math = (tokens, i) => math(tokens[i].content, false);
md.block.ruler.before('fence', 'spotter_display_math', (state, start, end, silent) => {
  const first = state.src.slice(state.bMarks[start] + state.tShift[start], state.eMarks[start]);
  const open = first.startsWith('$$') ? '$$' : first.startsWith('\\[') ? '\\[' : null;
  if (!open) return false;
  if (silent) return true;
  const close = open === '$$' ? '$$' : '\\]';
  let content = first.slice(2), next = start + 1;
  if (content.endsWith(close)) content = content.slice(0, -2);
  else {
    while (next < end) {
      const line = state.src.slice(state.bMarks[next], state.eMarks[next]); next++;
      if (line.trimEnd().endsWith(close)) { content += '\n' + line.trimEnd().slice(0, -2); break; }
      content += '\n' + line;
    }
  }
  const token = state.push('spotter_display_math', 'div', 0); token.content = content.trim(); token.map = [start, next];
  state.line = next;
  return true;
}, { alt: ['paragraph', 'reference', 'blockquote', 'list'] });
md.renderer.rules.spotter_display_math = (tokens, i) => `<div class="math">${math(tokens[i].content, true)}</div>`;
export function renderGrammarJSON(text) {
  let value;
  try { value = JSON.parse(text); } catch { return null; }
  const issues = Array.isArray(value) ? value : value?.issues;
  const corrected = Array.isArray(value) ? undefined : value?.corrected;
  if (!Array.isArray(value) && (!value || Object.keys(value).some(key => !['corrected', 'issues'].includes(key)))) return null;
  if (!Array.isArray(issues) || (corrected !== undefined && typeof corrected !== 'string')) return null;
  const rows = [];
  for (const issue of issues) {
    if (typeof issue === 'string') { rows.push(`<li>${escape(issue)}</li>`); continue; }
    if (!issue || typeof issue !== 'object' || Array.isArray(issue)) return null;
    if (Object.keys(issue).some(key => !['original', 'suggestion', 'correction', 'message', 'reason'].includes(key))) return null;
    const original = issue.original;
    const suggestion = issue.suggestion ?? issue.correction;
    const message = issue.message ?? issue.reason;
    if ([original, suggestion, message].some(part => part !== undefined && typeof part !== 'string')
        || (!message && !(original && suggestion))) return null;
    const change = original !== undefined && suggestion !== undefined
      ? `<strong>${escape(original)} → ${escape(suggestion)}</strong>` : '';
    rows.push(`<li>${change}${change && message ? '<br>' : ''}${message ? escape(message) : ''}</li>`);
  }
  const body = corrected === undefined ? '' : `<p style="white-space:pre-wrap">${escape(corrected)}</p>`;
  return `<section class="grammar-result">${body}${rows.length ? `<ul>${rows.join('')}</ul>` : '<p>No issues found.</p>'}</section>`;
}

export function renderMarkdown(text, grammar = false) {
  if (grammar) {
    const structured = renderGrammarJSON(text.trim());
    if (structured !== null) return structured;
  }
  return md.render(text, { grammar });
}
