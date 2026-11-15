// Builds the complete download for another player: dist/NibWhisper-<version>-Full.zip.
// It holds the three addons, Nib's helper and the start scripts, laid out as the README's install steps describe.
//
// Never included: API keys (.env, gemini-key.local), machine settings (bridge-settings.json), logs, tests,
// node_modules, the generated reply files, the retired reply-slot addons, and your own guide exports.
// Included, so the guide works out of the box: the route data and guide index built from RestedXP guides.
// That makes this zip for sharing with friends, not for publishing.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { zip } from './package-curseforge.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const secret = /AIza[0-9A-Za-z_-]{30,}|AQ\.[0-9A-Za-z_-]{30,}|sk-[A-Za-z0-9_-]{30,}|ghp_[A-Za-z0-9]{30,}/;

const files = (dir) => fs.readdirSync(path.join(root, dir), { withFileTypes: true }).flatMap(entry => {
  const relative = path.posix.join(dir, entry.name);
  return entry.isDirectory() ? files(relative) : [relative];
});
const excluded = file => /(^|\/)tests\//.test(file) || /(^|\/)node_modules\//.test(file) || /\/Fonts\/R\d{4}\.ttf$/.test(file)
  || /\.(tmp|log)$/i.test(file) || /(^|\/)\.env$/.test(file) || /gemini-key\.local$|bridge-settings\.json$|conversations/.test(file);

export function collectFull() {
  const list = [
    'README.md', 'CHANGELOG.md', 'Start-Nib-Auto.cmd', 'Start-Nib.cmd', 'Start-Nib.ps1', 'Start-Nib-Helper.ps1', 'Install-Nib.ps1', 'Open-Nib.cmd',
    ...files('addon/NibWhisper'), ...files('addon/NibWhisper_Guide'), ...files('addon/NibWhisper_Assistant'),
    'companion/server.mjs', 'companion/package.json', 'companion/package-lock.json', 'companion/tsconfig.json', 'companion/.env.example',
    'companion/README.md', 'companion/BACKEND.md',
    ...files('companion/lib'), ...files('companion/agent'), ...files('companion/public'),
    ...['guide-index.json', 'knowledge.json', 'provider-settings.json', 'trail-catalog.json', 'trail-starters.json'].map(name => `companion/data/${name}`),
    ...['capture-optical.ps1', 'optical-bridge.mjs', 'optical-protocol.mjs', 'font-transport.mjs'].map(name => `tools/${name}`),
  ].filter(file => !excluded(file));
  const missing = list.filter(file => !fs.existsSync(path.join(root, file)));
  if (missing.length) throw new Error(`Missing from the workspace: ${missing.join(', ')}`);
  const entries = list.map(file => {
    const data = fs.readFileSync(path.join(root, file));
    if (secret.test(data.toString('latin1'))) throw new Error(`${file} looks like it contains an API key. Nothing was packaged.`);
    return { name: `NibWhisper/${file}`, data };
  });
  const version = /^## Version:\s*(\S+)/m.exec(fs.readFileSync(path.join(root, 'addon/NibWhisper/NibWhisper.toc'), 'utf8'))[1];
  return { version, entries };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const { version, entries } = collectFull();
  const out = path.join(root, 'dist', `NibWhisper-${version}-Full.zip`);
  fs.mkdirSync(path.dirname(out), { recursive: true });
  fs.writeFileSync(out, zip(entries));
  console.log(`${path.relative(root, out)}: ${entries.length} files, ${(fs.statSync(out).size / 1048576).toFixed(1)} MB`);
}
