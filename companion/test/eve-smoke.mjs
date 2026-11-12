// A bounded no-model-call runtime/auth check. It never asks the agent a question.
import { spawn } from 'node:child_process';
import assert from 'node:assert/strict';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import crypto from 'node:crypto';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const port = 19862;
const token = crypto.randomBytes(32).toString('base64url');
let logs = '';
const child = spawn(process.execPath, [path.join(root, 'node_modules/eve/bin/eve.js'), 'dev', '--no-ui', '--no-default-extensions', '--host', '127.0.0.1', '--port', String(port)], { cwd: root, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'], env: { ...process.env, OPENAI_API_KEY: '', NIB_EVE_TOKEN: token, NIB_DATA_DIR: path.join(root, 'data') } });
child.stdout.on('data', data => { logs = (logs + data).slice(-16000); });
child.stderr.on('data', data => { logs = (logs + data).slice(-16000); });
try {
  const deadline = Date.now() + 50000;
  let healthy = false;
  while (Date.now() < deadline && child.exitCode === null) {
    try { const response = await fetch(`http://127.0.0.1:${port}/eve/v1/health`, { signal: AbortSignal.timeout(800) }); healthy = response.ok && (await response.json()).status === 'ready'; if (healthy) break; } catch {}
    await new Promise(resolve => setTimeout(resolve, 400));
  }
  assert(healthy, `Eve runtime did not become healthy.\n${logs}`);
  const unauth = await fetch(`http://127.0.0.1:${port}/eve/v1/info`);
  assert.equal(unauth.status, 401);
  const auth = await fetch(`http://127.0.0.1:${port}/eve/v1/info`, { headers: { authorization: `Bearer ${token}` } });
  assert.equal(auth.status, 200);
  const info = await auth.json();
  assert.equal(info.version, 5);
  assert.deepEqual(info.tools.static.map(tool => tool.name), ['lookup_warcraft']);
  assert.deepEqual(info.tools.dynamic, []);
  console.log(JSON.stringify({ runtime: 'eve', healthy: true, unauthorizedInfo: unauth.status, authorizedInfo: auth.status, version: info.version, tools: info.tools.static.map(tool => tool.name), noModelCalls: true }, null, 2));
} finally {
  child.kill('SIGTERM');
  await Promise.race([new Promise(resolve => child.once('exit', resolve)), new Promise(resolve => setTimeout(resolve, 4000))]);
}
