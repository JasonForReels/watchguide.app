// node render.mjs <slides|video> ... — renders screenshots or video frames with local Chrome.
import puppeteer from 'puppeteer-core';
import { pathToFileURL } from 'url';
import path from 'path';
import fs from 'fs';
const here = path.dirname(new URL(import.meta.url).pathname);
const browser = await puppeteer.launch({ executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  headless: true, args: ['--allow-file-access-from-files', '--hide-scrollbars', '--force-color-profile=srgb'] });
const page = await browser.newPage();
const [mode, outDir] = process.argv.slice(2);
// WG_LANG=zh renders the Chinese captions.
// WG_VARIANT=soon renders the coming-soon cut of update.html; WG_CUT=long the ~90 s YouTube cut.
const Q = [process.env.WG_LANG && `lang=${process.env.WG_LANG}`, process.env.WG_VARIANT && `variant=${process.env.WG_VARIANT}`, process.env.WG_CUT && `cut=${process.env.WG_CUT}`].filter(Boolean).join('&');
fs.mkdirSync(outDir, { recursive: true });
// Timeline pages (window.TIMELINE + window.render(t)); sample-<key> renders a few stills.
const VIDEO = {
  video: { file: 'video.html', w: 886, h: 1920 },
  'video-ipad': { file: 'video-ipad.html', w: 1200, h: 1600 },
  ipad: { file: 'video-ipad.html', w: 1200, h: 1600 },
  ad: { file: 'ad.html', w: 1080, h: 1920 },
  hello: { file: 'hello.html', w: 1920, h: 1080 },
  update: { file: 'update.html', w: 1920, h: 1080 },
};
if (mode === 'tv') {
  // Apple TV screenshots: node render.mjs tv <outDir> <capturesDir>; captures are
  // <lang>_<screen>.png (zh uses the English UI, as the app isn't in Chinese).
  const screens = ['browse', 'tonight', 'search', 'streamq', 'lists'];
  const lang = process.env.WG_LANG || 'en';
  const caps = path.resolve(process.argv[4]);
  await page.setViewport({ width: 1920, height: 1080, deviceScaleFactor: 1 });
  for (let i = 0; i < screens.length; i++) {
    const shot = pathToFileURL(path.join(caps, `${lang === 'es' ? 'es' : 'en'}_${screens[i]}.png`)).href;
    await page.goto(pathToFileURL(path.join(here, 'slide-tv.html')).href + `?s=${i + 1}&lang=${lang}&shot=${encodeURIComponent(shot)}`, { waitUntil: 'networkidle0' });
    await page.evaluate(() => document.fonts.ready);
    await page.screenshot({ path: path.join(outDir, `0${i + 1}-${screens[i]}.png`) });
  }
} else if (mode === 'header') {
  // Universal creative asset (16:9). GUIDES=1 draws the header and search-result crops.
  await page.setViewport({ width: 5244, height: 2950, deviceScaleFactor: 1 });
  const guides = process.env.GUIDES ? '&guides=1' : '';
  await page.goto(pathToFileURL(path.join(here, 'header.html')).href + `?${Q}${guides}`, { waitUntil: 'networkidle0' });
  await page.evaluate(() => document.fonts.ready);
  await page.screenshot({ path: path.join(outDir, 'universal-raw.png') });
} else if (mode === 'promo') {
  // Release announcement images for social posts: promo-4x5.png, promo-16x9.png and promo-9x16.png.
  for (const [name, w, h, q] of [['promo-4x5', 2160, 2700, ''], ['promo-16x9', 3840, 2160, '?ar=wide'], ['promo-9x16', 2160, 3840, '?ar=tall']]) {
    await page.setViewport({ width: w, height: h, deviceScaleFactor: 1 });
    await page.goto(pathToFileURL(path.join(here, 'promo.html')).href + q + (Q ? (q ? '&' : '?') + Q : ''), { waitUntil: 'networkidle0' });
    await page.evaluate(() => document.fonts.ready);
    await page.screenshot({ path: path.join(outDir, `${name}.png`) });
  }
} else if (mode === 'slides' || mode === 'slides-ipad') {
  const ipad = mode === 'slides-ipad';
  await page.setViewport(ipad ? { width: 2064, height: 2752, deviceScaleFactor: 1 } : { width: 1320, height: 2868, deviceScaleFactor: 1 });
  for (let i = 1; i <= 6; i++) {
    await page.goto(pathToFileURL(path.join(here, ipad ? 'slide-ipad.html' : 'slide.html')).href + `?s=${i}&${Q}`, { waitUntil: 'networkidle0' });
    await page.evaluate(() => document.fonts.ready);
    await page.screenshot({ path: path.join(outDir, `0${i}.png`) });
  }
} else if (mode.startsWith('sample')) {
  const v = VIDEO[mode.slice(7) || 'video'];
  await page.setViewport({ width: v.w, height: v.h, deviceScaleFactor: 1 });
  await page.goto(pathToFileURL(path.join(here, v.file)).href + `?${Q}`, { waitUntil: 'networkidle0' });
  await page.evaluate(() => document.fonts.ready);
  console.log(JSON.stringify(await page.evaluate(() => window.TIMELINE)));
  for (const t of process.argv.slice(4).map(Number)) {
    await page.evaluate(t => window.render(t), t);
    await page.screenshot({ path: path.join(outDir, `s_${t.toFixed(2)}.jpg`), type: 'jpeg', quality: 85 });
  }
} else {
  // modes: video (App Preview), video-ipad, ad (1080x1920 social ad), hello (1920x1080 5.6.1 launch)
  const v = VIDEO[mode];
  await page.setViewport({ width: v.w, height: v.h, deviceScaleFactor: 1 });
  await page.goto(pathToFileURL(path.join(here, v.file)).href + `?${Q}`, { waitUntil: 'networkidle0' });
  await page.evaluate(() => document.fonts.ready);
  const { total, fps } = await page.evaluate(() => window.TIMELINE);
  const frames = Math.round(total * fps);
  for (let f = 0; f < frames; f++) {
    await page.evaluate(t => window.render(t), f / fps);
    await page.screenshot({ path: path.join(outDir, `f${String(f).padStart(5, '0')}.jpg`), type: 'jpeg', quality: 92 });
    if (f % 90 === 0) console.log(`frame ${f}/${frames}`);
  }
  console.log(`done ${frames} frames`);
}
await browser.close();
