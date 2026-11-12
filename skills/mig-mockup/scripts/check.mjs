#!/usr/bin/env node
// Screenshot mockups at desktop and phone widths and flag horizontal overflow.
// Needs Node 22 or later (built-in WebSocket) and Chrome or Chromium. No npm packages.
//
// Usage: node check.mjs <file.html | folder | http URL>... [--out <dir>] [--widths 1440,390]
// A folder means every .html file in it except index.html. A URL is the current page, saved as before-<host>-<path>.
// Screenshots go to <out>/<name>-<width>.png (default: shots/ next to the first input).
// Exit code 0: every page fits. 1: a page overflows or failed to load. 2: usage or setup error.

import { spawn } from 'node:child_process';
import { existsSync, mkdirSync, readdirSync, statSync, writeFileSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { basename, dirname, join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const args = process.argv.slice(2);
const flag = (name, fallback) => {
  const i = args.indexOf(name);
  if (i === -1) return fallback;
  const value = args[i + 1];
  args.splice(i, 2);
  return value;
};
const widths = flag('--widths', '1440,390').split(',').map(Number);
let outDir = flag('--out', null);

if (args.length === 0) {
  console.error('Usage: node check.mjs <file.html | folder | URL>... [--out <dir>] [--widths 1440,390]');
  process.exit(2);
}
if (typeof WebSocket === 'undefined') {
  console.error('This script needs Node 22 or later.');
  process.exit(2);
}

const pages = [];
for (const arg of args) {
  if (/^https?:\/\//.test(arg)) {
    const u = new URL(arg);
    const name = ('before-' + u.hostname + u.pathname).replace(/\.html$/, '').replace(/[^a-z0-9.-]+/gi, '-').replace(/-+$/, '');
    pages.push({ name, url: arg });
  } else if (existsSync(arg) && statSync(arg).isDirectory()) {
    for (const f of readdirSync(arg).filter((f) => f.endsWith('.html') && f !== 'index.html').sort()) {
      pages.push({ name: f.replace(/\.html$/, ''), url: pathToFileURL(resolve(arg, f)).href });
    }
    outDir ??= join(arg, 'shots');
  } else if (existsSync(arg)) {
    pages.push({ name: basename(arg).replace(/\.html$/, ''), url: pathToFileURL(resolve(arg)).href });
    outDir ??= join(dirname(arg), 'shots');
  } else {
    console.error(`Not found: ${arg}`);
    process.exit(2);
  }
}
outDir ??= 'shots';
mkdirSync(outDir, { recursive: true });

const chromePath = [
  process.env.CHROME,
  '/usr/bin/google-chrome',
  '/usr/bin/chromium',
  '/usr/bin/chromium-browser',
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
].find((p) => p && existsSync(p));
if (!chromePath) {
  console.error('Chrome not found. Set CHROME to its path.');
  process.exit(2);
}

const profile = mkdtempSync(join(tmpdir(), 'mockup-check-'));
const chrome = spawn(chromePath, [
  '--headless=new', '--remote-debugging-port=0', `--user-data-dir=${profile}`,
  '--no-first-run', '--no-default-browser-check', '--hide-scrollbars', '--ignore-certificate-errors', 'about:blank',
], { stdio: ['ignore', 'ignore', 'pipe'] });

const wsUrl = await new Promise((ok, fail) => {
  let buf = '';
  const timer = setTimeout(() => fail(new Error('Chrome did not start within 15 seconds')), 15000);
  chrome.stderr.on('data', (d) => {
    buf += d;
    const m = buf.match(/DevTools listening on (ws:\/\/\S+)/);
    if (m) { clearTimeout(timer); ok(m[1]); }
  });
  chrome.on('exit', () => fail(new Error('Chrome exited early')));
});

const ws = new WebSocket(wsUrl);
await new Promise((ok) => ws.addEventListener('open', ok, { once: true }));
let nextId = 0;
const pending = new Map();
const listeners = [];
ws.addEventListener('message', (e) => {
  const msg = JSON.parse(e.data);
  if (msg.id && pending.has(msg.id)) {
    const { ok, fail } = pending.get(msg.id);
    pending.delete(msg.id);
    msg.error ? fail(new Error(msg.error.message)) : ok(msg.result);
  } else if (msg.method) {
    for (const l of listeners) l(msg);
  }
});
const send = (method, params = {}, sessionId) => new Promise((ok, fail) => {
  const id = ++nextId;
  pending.set(id, { ok, fail });
  ws.send(JSON.stringify({ id, method, params, sessionId }));
});
const waitFor = (method, sessionId, ms = 20000) => new Promise((ok, fail) => {
  const timer = setTimeout(() => fail(new Error(`Timed out waiting for ${method}`)), ms);
  const l = (msg) => {
    if (msg.method === method && msg.sessionId === sessionId) {
      clearTimeout(timer);
      listeners.splice(listeners.indexOf(l), 1);
      ok(msg.params);
    }
  };
  listeners.push(l);
});

const overflowProbe = `(() => {
  const vw = document.documentElement.clientWidth;
  const offenders = [];
  for (const el of document.querySelectorAll('body *')) {
    const r = el.getBoundingClientRect();
    if (r.width > 0 && r.right > vw + 1 && getComputedStyle(el).position !== 'fixed') {
      offenders.push((el.tagName.toLowerCase() + (el.id ? '#' + el.id : '') + (el.classList[0] ? '.' + el.classList[0] : '')) + ' right=' + Math.round(r.right));
      if (offenders.length === 5) break;
    }
  }
  return { scrollWidth: document.documentElement.scrollWidth, viewport: vw, offenders };
})()`;

let failures = 0;
const results = [];
for (const page of pages) {
  for (const width of widths) {
    const { targetId } = await send('Target.createTarget', { url: 'about:blank' });
    const { sessionId } = await send('Target.attachToTarget', { targetId, flatten: true });
    try {
      await send('Page.enable', {}, sessionId);
      await send('Emulation.setDeviceMetricsOverride', {
        width, height: width < 600 ? 844 : 900, deviceScaleFactor: 1, mobile: width < 600,
      }, sessionId);
      const loaded = waitFor('Page.loadEventFired', sessionId);
      await send('Page.navigate', { url: page.url }, sessionId);
      await loaded;
      await send('Runtime.evaluate', { expression: 'document.fonts.ready', awaitPromise: true }, sessionId);
      const { result } = await send('Runtime.evaluate', { expression: overflowProbe, returnByValue: true }, sessionId);
      const probe = result.value;
      const shot = await send('Page.captureScreenshot', { format: 'png', captureBeyondViewport: true }, sessionId);
      const file = join(outDir, `${page.name}-${width}.png`);
      writeFileSync(file, Buffer.from(shot.data, 'base64'));
      const overflow = probe.scrollWidth > probe.viewport + 1;
      if (overflow) failures++;
      results.push(`${overflow ? 'OVERFLOW' : 'ok      '} ${page.name} @${width}  ${file}` +
        (overflow ? `\n         scrollWidth ${probe.scrollWidth} > ${probe.viewport}: ${probe.offenders.join(', ')}` : ''));
    } catch (err) {
      failures++;
      results.push(`ERROR    ${page.name} @${width}  ${err.message}`);
    } finally {
      await send('Target.closeTarget', { targetId });
    }
  }
}

console.log(results.join('\n'));
ws.close();
chrome.kill();
await new Promise((ok) => setTimeout(ok, 300));
rmSync(profile, { recursive: true, force: true });
process.exit(failures ? 1 : 0);
