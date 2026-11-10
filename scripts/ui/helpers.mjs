// Shared set-up for UI tests on the web build: a static server for dist/ (single-page app) and Chromium.
import assert from 'node:assert/strict';
import { createReadStream, existsSync, mkdirSync, statSync } from 'node:fs';
import { createServer } from 'node:http';
import { createRequire } from 'node:module';
import { extname, join, normalize } from 'node:path';

const require = createRequire(import.meta.url);
const { chromium } = require('playwright');

const DIST = 'dist';
export const SCREENSHOTS = 'ui-screenshots'; // uploaded by CI; never committed
const TYPES = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.ttf': 'font/ttf', '.json': 'application/json', '.png': 'image/png', '.ico': 'image/x-icon' };

export async function startWeb() {
  assert.ok(existsSync(join(DIST, 'index.html')), 'run `npm run export:web` first');
  mkdirSync(SCREENSHOTS, { recursive: true });
  const server = createServer((req, res) => {
    const path = normalize(decodeURIComponent(new URL(req.url, 'http://x').pathname)).replace(/^(\.\.[/\\])+/, '');
    let file = join(DIST, path);
    if (!existsSync(file) || statSync(file).isDirectory()) file = join(DIST, 'index.html');
    res.setHeader('content-type', TYPES[extname(file)] ?? 'application/octet-stream');
    createReadStream(file).pipe(res);
  });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const browser = await chromium.launch();
  return {
    base: `http://127.0.0.1:${server.address().port}`,
    browser,
    async stop() {
      await browser.close();
      server.close();
    },
  };
}
