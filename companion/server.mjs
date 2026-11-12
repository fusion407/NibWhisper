import path from 'node:path';
import { fileURLToPath } from 'node:url';
import crypto from 'node:crypto';
import { spawn } from 'node:child_process';
import { createAssistant, createEveRuntime } from './lib/assistant.mjs';
import { createHttpServer } from './lib/http.mjs';
import { NibError } from './lib/protocol.mjs';
import { getProviderStatus } from './lib/providers.mjs';
import { createTrailSync, resolveTrailFolder } from './lib/trail-sync.mjs';
import { createGeminiRuntime, getGeminiKey } from './lib/gemini.mjs';

const root = path.dirname(fileURLToPath(import.meta.url));
try { process.loadEnvFile(path.join(root, '.env')); } catch (error) { if (error.code !== 'ENOENT') throw error; }
const port = Number(process.env.NIB_PORT || 17861);
const evePort = Number(process.env.NIB_EVE_PORT || 17862);
if (![port, evePort].every(p => Number.isInteger(p) && p >= 1024 && p <= 65535) || port === evePort) throw new Error('Nib ports must be distinct integers from 1024 through 65535.');
const dataDir = path.join(root, 'data');
const gemini = createGeminiRuntime({ dataDir });
const providerConfig = async () => {
  const selection = await getProviderStatus(dataDir);
  if (selection.provider === 'gemini') selection.configured = Boolean(await getGeminiKey(dataDir));
  return selection;
};
const eveToken = crypto.randomBytes(32).toString('base64url');
const baseUrl = `http://127.0.0.1:${evePort}`;
let child;
let opticalChild;
let opticalError = null;
let runtimeError = null;
let stopping = false;

if (process.env.OPENAI_API_KEY?.trim()) {
  child = spawn(process.execPath, [path.join(root, 'node_modules/eve/bin/eve.js'), 'dev', '--no-ui', '--no-default-extensions', '--host', '127.0.0.1', '--port', String(evePort)], {
    cwd: root, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'],
    env: { ...process.env, NIB_EVE_TOKEN: eveToken, NIB_DATA_DIR: path.join(root, 'data'), EVE_TELEMETRY_DISABLED: '1' }
  });
  child.stdout.on('data', bytes => process.stdout.write(`[eve] ${bytes}`));
  child.stderr.on('data', bytes => process.stderr.write(`[eve] ${bytes}`));
  child.on('error', () => { runtimeError = 'Eve could not start. Run npm ci in the companion folder.'; });
  child.on('exit', code => { if (!stopping) runtimeError = `Eve stopped (exit ${code ?? 'signal'}). Restart the companion.`; });
}

const runtime = createEveRuntime({ baseUrl, token: eveToken });
const assistant = createAssistant({ runtime: { generate: async (request, ...args) => {
  if (request.capabilities.provider === 'gemini') return gemini.generate(request, ...args);
  if (runtimeError) throw new NibError(runtimeError, 503, 'runtime_not_ready');
  return runtime.generate(request, ...args);
} }, dataDir, providerConfig });
const trailSync=createTrailSync({dataDir:path.join(root,'data')});
const app = createHttpServer({ assistant, trailSync, gemini, providerConfig, port, publicDir: path.join(root, 'public'), dataDir, status: async () => {
  const selection = await providerConfig();
  const google = selection.provider === 'gemini';
  let ready = google && selection.configured;
  if (!google && selection.configured && !runtimeError) try { const result = await fetch(`${baseUrl}/eve/v1/health`, { signal: AbortSignal.timeout(1000), redirect: 'error' }); ready = result.ok && (await result.json()).status === 'ready'; } catch {}
  const setupMessage = !selection.configured ? (google ? 'Save a Gemini API key below.' : `Add ${selection.credentialEnv} to companion/.env and restart.`) : (ready ? 'Ready to ask.' : runtimeError ?? 'Starting the OpenAI runtime. Check the connection again shortly.');
  return { ...selection, ready, trailSyncAvailable:Boolean(await resolveTrailFolder().catch(()=>null)), runtime: google ? 'gemini' : 'eve', bridgeVersion: 4, opticalEnabled: Boolean(opticalChild && opticalChild.exitCode === null && !opticalError), opticalError, setupMessage, researchOnly: false };
} });

await app.listen();
console.log(`Nib companion: http://127.0.0.1:${port}`);
console.log(await resolveTrailFolder().catch(()=>null) ? 'Nib Trail: shared folder configured. Enable Cloud sync in the in-game Trail panel.' : 'Nib Trail: no shared folder configured. Manual progress export still works.');
if (!(await providerConfig()).configured) console.log('Open the companion page to connect Gemini. Guide chat in WoW is available now.');
if (process.platform === 'win32' && process.env.NIB_OPEN_BROWSER === '1') {
  const browser = spawn('explorer.exe', [`http://127.0.0.1:${port}/`], { windowsHide: true, stdio: 'ignore' });
  browser.on('error', () => console.log('Open the companion URL above in your browser.'));
  browser.unref();
}
if (process.env.NIB_OPTICAL_ADDONS) {
  if (port !== 17861) opticalError = 'Optical transport currently requires NIB_PORT=17861.';
  else {
    opticalChild = spawn(process.execPath, [path.join(root, '../tools/optical-bridge.mjs'), '--watch-screen', '--addons', process.env.NIB_OPTICAL_ADDONS], { cwd: root, windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'], env: { ...process.env, NIB_BRIDGE_PARENT_PID: String(process.pid) } });
    opticalChild.stdout.on('data', bytes => process.stdout.write(`[optical] ${bytes}`));
    opticalChild.stderr.on('data', bytes => process.stderr.write(`[optical] ${bytes}`));
    opticalChild.on('error', () => { opticalError = 'Optical helper could not start. Manual transport remains available.'; });
    opticalChild.on('exit', code => { if (!stopping) opticalError = `Optical helper stopped (exit ${code ?? 'signal'}). Manual transport remains available.`; });
  }
}
const stop = () => {
  if (stopping) return;
  stopping = true;
  app.server.close();
  child?.kill('SIGTERM');
  // EOF lets the helper stop its owned capture worker before Windows terminates it.
  opticalChild?.stdin?.end();
  setTimeout(() => process.exit(0), 2500).unref();
};
process.on('SIGINT', stop); process.on('SIGTERM', stop);
