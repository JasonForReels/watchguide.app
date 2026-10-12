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
const Q = process.env.WG_LANG ? `lang=${process.env.WG_LANG}` : '';
fs.mkdirSync(outDir, { recursive: true });
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
} else if (mode === 'slides' || mode === 'slides-ipad') {
  const ipad = mode === 'slides-ipad';
  await page.setViewport(ipad ? { width: 2064, height: 2752, deviceScaleFactor: 1 } : { width: 1320, height: 2868, deviceScaleFactor: 1 });
  for (let i = 1; i <= 6; i++) {
    await page.goto(pathToFileURL(path.join(here, ipad ? 'slide-ipad.html' : 'slide.html')).href + `?s=${i}&${Q}`, { waitUntil: 'networkidle0' });
    await page.evaluate(() => document.fonts.ready);
    await page.screenshot({ path: path.join(outDir, `0${i}.png`) });
  }
} else if (mode === 'sample' || mode === 'sample-ipad' || mode === 'sample-ad') {
  const ipad = mode === 'sample-ipad', ad = mode === 'sample-ad';
  await page.setViewport(ad ? { width: 1080, height: 1920, deviceScaleFactor: 1 } : ipad ? { width: 1200, height: 1600, deviceScaleFactor: 1 } : { width: 886, height: 1920, deviceScaleFactor: 1 });
  await page.goto(pathToFileURL(path.join(here, ad ? 'ad.html' : ipad ? 'video-ipad.html' : 'video.html')).href + `?${Q}`, { waitUntil: 'networkidle0' });
  console.log(JSON.stringify(await page.evaluate(() => window.TIMELINE)));
  for (const t of process.argv.slice(4).map(Number)) {
    await page.evaluate(t => window.render(t), t);
    await page.screenshot({ path: path.join(outDir, `s_${t.toFixed(2)}.jpg`), type: 'jpeg', quality: 85 });
  }
} else {
  // modes: video (App Preview), video-ipad, ad (1080x1920 social ad)
  const ipad = mode === 'video-ipad', ad = mode === 'ad';
  await page.setViewport(ad ? { width: 1080, height: 1920, deviceScaleFactor: 1 } : ipad ? { width: 1200, height: 1600, deviceScaleFactor: 1 } : { width: 886, height: 1920, deviceScaleFactor: 1 });
  await page.goto(pathToFileURL(path.join(here, ad ? 'ad.html' : ipad ? 'video-ipad.html' : 'video.html')).href + `?${Q}`, { waitUntil: 'networkidle0' });
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
