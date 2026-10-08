import { build } from 'esbuild';
import fs from 'node:fs';
import path from 'node:path';
const out = '../../Spotter/Resources/AIChatMarkdown';
await build({ entryPoints: ['renderer.mjs'], bundle: true, minify: true, format: 'iife', platform: 'browser', target: 'safari18', outfile: `${out}/renderer.js`, legalComments: 'eof' });
fs.copyFileSync('node_modules/katex/dist/katex.min.css', `${out}/katex.min.css`);
fs.mkdirSync(`${out}/fonts`, { recursive: true });
for (const file of fs.readdirSync('node_modules/katex/dist/fonts').filter(x => x.endsWith('.woff2'))) fs.copyFileSync(`node_modules/katex/dist/fonts/${file}`, `${out}/fonts/${file}`);
const licenses = [];
function scan(directory) {
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    if (!entry.isDirectory() || entry.name.startsWith('.')) continue;
    const folder = path.join(directory, entry.name);
    if (entry.name.startsWith('@')) { scan(folder); continue; }
    const manifest = path.join(folder, 'package.json');
    if (fs.existsSync(manifest)) {
      const pkg = JSON.parse(fs.readFileSync(manifest, 'utf8'));
      const license = fs.readdirSync(folder).find(x => /^licen[sc]e(?:\.|$)/i.test(x));
      if (license && fs.statSync(path.join(folder, license)).isFile()) licenses.push(`${pkg.name} ${pkg.version}\n${fs.readFileSync(path.join(folder, license), 'utf8')}`);
    }
    if (fs.existsSync(path.join(folder, 'node_modules'))) scan(path.join(folder, 'node_modules'));
  }
}
scan('node_modules');
fs.writeFileSync(`${out}/LICENSES.txt`, licenses.join('\n\n---------------\n\n'));
