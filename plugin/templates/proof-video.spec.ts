// Proof recording template. One test per scene; each scene is one checklist proof item.
// Copy to the project's e2e dir as proof-<slice>.spec.ts, set BASE and the scenes, run:
//   npx playwright test proof-<slice>.spec.ts --project=chromium
// Videos land in proof/<slice>/scenes/NN-<name>.webm; then: bash <plugin>/scripts/proof-video.sh <slice>
import { test, chromium } from '@playwright/test';
import fs from 'node:fs'; import path from 'node:path';
const SLICE = process.env.PROOF_SLICE ?? 'slice';
const BASE = process.env.PROOF_BASE ?? 'http://localhost:5174';
const OUT = path.resolve(process.env.PROOF_DIR ?? 'proof', SLICE, 'scenes');
fs.mkdirSync(OUT, { recursive: true });
async function scene(n: number, name: string, drive: (page: import('@playwright/test').Page) => Promise<void>) {
  const browser = await chromium.launch();
  const ctx = await browser.newContext({ recordVideo: { dir: OUT, size: { width: 1280, height: 720 } }, viewport: { width: 1280, height: 720 } });
  const page = await ctx.newPage();
  try { await drive(page); await page.waitForTimeout(800); } finally {
    const v = page.video(); await ctx.close(); await browser.close();
    if (v) fs.renameSync(await v.path(), path.join(OUT, `${String(n).padStart(2, '0')}-${name}.webm`));
  }
}
test('scene 1: sign in', async () => scene(1, 'sign-in', async (p) => { await p.goto(`${BASE}/staff/`); }));
// add one test per checklist proof item; keep names short, they become the srt order
