import http from 'node:http';
import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { NibError, MAX_PACKET_BYTES, sampleRequest, encodePacket, plainObject } from './protocol.mjs';
import { loadKnowledge } from './knowledge.mjs';
import { getProviderStatus, saveProviderSettings } from './providers.mjs';

const PUBLIC_DIR = fileURLToPath(new URL('../public/', import.meta.url));
const MIME = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8', '.svg': 'image/svg+xml', '.png': 'image/png', '.webp': 'image/webp', '.ico': 'image/x-icon' };

async function readJson(request, limit = MAX_PACKET_BYTES + 16000) {
  if (request.headers['content-type']?.split(';')[0].trim() !== 'application/json') throw new NibError('Use application/json.', 415, 'content_type');
  let length = 0;
  const parts = [];
  for await (const part of request) {
    length += part.length;
    if (length > limit) throw new NibError('Request body is too large.', 413, 'body_too_large');
    parts.push(part);
  }
  try { const value = JSON.parse(Buffer.concat(parts).toString('utf8')); if (!plainObject(value)) throw new Error(); return value; }
  catch { throw new NibError('Request body must be a JSON object.'); }
}

export function createHttpServer({ assistant, trailSync, gemini, providerConfig = () => getProviderStatus(dataDir), port = 17861, publicDir = PUBLIC_DIR, dataDir, status = async () => ({}), csrfToken = crypto.randomBytes(32).toString('base64url') } = {}) {
  const allowedHosts = new Set([`127.0.0.1:${port}`, `localhost:${port}`]);
  let lastAccepted = 0;
  const server = http.createServer(async (request, response) => {
    response.setHeader('cache-control', 'no-store');
    response.setHeader('x-content-type-options', 'nosniff');
    response.setHeader('referrer-policy', 'no-referrer');
    response.setHeader('content-security-policy', "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'");
    const json = (code, value) => { response.writeHead(code, { 'content-type': 'application/json; charset=utf-8' }); response.end(JSON.stringify(value)); };
    try {
      const actualPort = server.address()?.port ?? port;
      if (!allowedHosts.has(request.headers.host) && !(port === 0 && [`127.0.0.1:${actualPort}`, `localhost:${actualPort}`].includes(request.headers.host))) throw new NibError('Localhost access only.', 403, 'host_rejected');
      const origin = request.headers.origin;
      if (origin && origin !== `http://${request.headers.host}`) throw new NibError('Cross-origin access is not allowed.', 403, 'origin_rejected');
      if (request.headers['sec-fetch-site'] && !['same-origin', 'none'].includes(request.headers['sec-fetch-site'])) throw new NibError('Cross-site access is not allowed.', 403, 'origin_rejected');
      const url = new URL(request.url, `http://${request.headers.host}`);
      if (url.pathname === '/api/status' && request.method === 'GET') {
        const info = await status();
        const data = await loadKnowledge(dataDir);
        return json(200, { ok: true, csrfToken, transport: 'manual', manualTransport: true, guideCount: data.guides.length, seedCount: data.entries.length, busy: assistant.busy, ...info });
      }
      if (url.pathname === '/api/sample' && request.method === 'GET') {
        const requestValue = sampleRequest();
        return json(200, { sample: true, request: requestValue, packet: encodePacket('NIBQ1', requestValue) });
      }
      if (url.pathname.startsWith('/api/')) {
        if (request.method !== 'POST') throw new NibError('Unsupported method.', 405, 'method_not_allowed');
        const submitted = request.headers['x-nib-token'];
        if (typeof submitted !== 'string' || submitted.length !== csrfToken.length || !crypto.timingSafeEqual(Buffer.from(submitted), Buffer.from(csrfToken))) throw new NibError('Refresh the companion page to obtain a fresh session token.', 403, 'csrf_rejected');
        if (!origin) throw new NibError('An exact localhost Origin header is required.', 403, 'origin_required');
        if (url.pathname === '/api/trail-sync') {
          if (!trailSync) throw new NibError('Trail sync is unavailable on this companion.',503,'sync_not_configured');
          const {packet} = await readJson(request);
          return json(200, await trailSync.exchange(packet));
        }
        if (url.pathname === '/api/settings') {
          if (assistant.busy) throw new NibError('Wait for Nib to finish the current reply before switching models.', 409, 'busy');
          await saveProviderSettings(await readJson(request), dataDir);
          assistant.clear();
          return json(200, { ok: true, settings: await providerConfig() });
        }
        if (url.pathname === '/api/gemini-key') {
          if (!gemini) throw new NibError('Gemini setup is unavailable on this companion.', 503, 'setup_unavailable');
          if (assistant.busy) throw new NibError('Wait for Nib to finish the current reply before changing keys.', 409, 'busy');
          await gemini.saveKey(await readJson(request, 2048));
          assistant.clear();
          return json(200, { ok: true });
        }
        if (url.pathname === '/api/clear') {
          await readJson(request);
          assistant.clear();
          return json(200, { ok: true, message: 'Transient companion state cleared. The addon history and provider/workflow retention are separate.' });
        }
        if (url.pathname !== '/api/ask') throw new NibError('Unknown API route.', 404, 'not_found');
        if (Date.now() - lastAccepted < 750) throw new NibError('Please wait a moment before sending another request.', 429, 'rate_limit');
        const body = await readJson(request);
        if (Object.keys(body).some(k => !['packet', 'question'].includes(k))) throw new NibError('Unknown request fields. Only packet and question are accepted.');
        lastAccepted = Date.now();
        const abort = new AbortController();
        response.on('close', () => { if (!response.writableFinished) abort.abort(); });
        return json(200, await assistant.handleAsk(body, { signal: abort.signal }));
      }
      if (!['GET', 'HEAD'].includes(request.method)) throw new NibError('Unsupported method.', 405, 'method_not_allowed');
      let pathname;
      try { pathname = decodeURIComponent(url.pathname); } catch { throw new NibError('Invalid path.'); }
      if (pathname === '/') pathname = '/index.html';
      if (pathname.includes('\\') || pathname.split('/').some(part => part.startsWith('.'))) throw new NibError('Unknown asset.', 404, 'not_found');
      const file = path.resolve(publicDir, `.${pathname}`);
      if (!file.startsWith(path.resolve(publicDir) + path.sep) || !MIME[path.extname(file)]) throw new NibError('Unknown asset.', 404, 'not_found');
      let bytes; try { bytes = await fs.readFile(file); } catch { throw new NibError('Companion UI asset not found.', 404, 'not_found'); }
      response.writeHead(200, { 'content-type': MIME[path.extname(file)], 'content-length': bytes.length });
      response.end(request.method === 'HEAD' ? undefined : bytes);
    } catch (error) {
      if (response.headersSent) return response.end();
      json(error instanceof NibError ? error.status : 500, { error: error instanceof NibError ? error.message : 'Nib encountered a local error. Restart the companion and try again.', code: error instanceof NibError ? error.code : 'internal_error' });
    }
  });
  server.requestTimeout = 150000;
  server.headersTimeout = 15000;
  return { server, csrfToken, listen: () => new Promise((resolve, reject) => { server.once('error', reject); server.listen(port, '127.0.0.1', () => { server.off('error', reject); resolve(server.address()); }); }) };
}
