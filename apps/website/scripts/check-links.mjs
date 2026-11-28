// Fails the build when a page in the built site links to a local page or file
// that does not exist, or is missing the SEO tags every page must carry.
import { readdirSync, readFileSync, existsSync, statSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { gzipSync } from 'node:zlib';
import { pathToFileURL } from 'node:url';

export function htmlFiles(dir) {
  return readdirSync(dir).flatMap((name) => {
    const path = join(dir, name);
    if (statSync(path).isDirectory()) return htmlFiles(path);
    return name.endsWith('.html') ? [path] : [];
  });
}

export function resolveLocal(dist, href) {
  const path = decodeURIComponent(href.split(/[?#]/)[0]);
  if (path === '/' || path === '') return join(dist, 'index.html');
  const candidates = [join(dist, path), join(dist, `${path}.html`), join(dist, path, 'index.html')];
  return candidates.find((c) => existsSync(c) && statSync(c).isFile()) ?? null;
}

export function checkPage(dist, file, html) {
  const problems = [];
  const page = relative(dist, file);
  for (const [, attr] of html.matchAll(/\s(?:href|src)="([^"]+)"/g)) {
    if (!attr.startsWith('/') || attr.startsWith('//')) continue;
    if (!resolveLocal(dist, attr)) problems.push(`${page}: broken local link ${attr}`);
  }
  // A noindex page (the 404) must not claim a canonical URL; every other page needs one.
  const noindex = html.includes('name="robots" content="noindex"');
  const required = ['<title>', 'name="description"', noindex ? null : 'rel="canonical"', 'property="og:image"', 'application/ld+json'].filter(Boolean);
  if (noindex && html.includes('rel="canonical"')) problems.push(`${page}: noindex page has a canonical link`);
  for (const tag of required) {
    if (!html.includes(tag)) problems.push(`${page}: missing ${tag}`);
  }
  return problems;
}

// Gzipped bytes of the JavaScript a built page runs: its module scripts, the
// modules those import, and inline module scripts. Each file counts once.
export function jsBudget(dist, page) {
  const html = readFileSync(join(dist, page), 'utf8');
  const seen = new Set();
  let total = 0;
  const addFile = (file) => {
    if (seen.has(file) || !existsSync(file)) return;
    seen.add(file);
    const code = readFileSync(file, 'utf8');
    total += gzipSync(code).length;
    for (const [, spec] of code.matchAll(/(?:from|import)\s*["'](\.{1,2}\/[^"']+\.m?js)["']/g)) addFile(join(dirname(file), spec));
  };
  for (const [, attrs, body] of html.matchAll(/<script([^>]*)>([\s\S]*?)<\/script>/g)) {
    if (!/type="module"/.test(attrs)) continue;
    const src = /src="([^"]+)"/.exec(attrs);
    if (src) addFile(join(dist, decodeURIComponent(src[1])));
    else total += gzipSync(body).length;
  }
  return total;
}

export function checkBudget(totalBytes, limit, page) {
  return totalBytes > limit ? `${page}: ${totalBytes} B of gzipped JavaScript is over the ${limit} B budget` : null;
}

// Home page: the 2,864 B it shipped before the scroll scenes, plus 12 KiB.
export const HOME_JS_LIMIT = 2864 + 12288;

export function isMain(moduleUrl, argvPath) {
  return Boolean(argvPath) && moduleUrl === pathToFileURL(argvPath).href;
}

if (isMain(import.meta.url, process.argv[1])) {
  const dist = process.argv[2] ?? 'dist';
  const files = htmlFiles(dist);
  const problems = files.flatMap((f) => checkPage(dist, f, readFileSync(f, 'utf8')));
  const home = existsSync(join(dist, 'index.html')) ? jsBudget(dist, 'index.html') : 0;
  const over = checkBudget(home, HOME_JS_LIMIT, 'index.html');
  if (over) problems.push(over);
  console.log(`Home page JavaScript: ${home} B gzipped of ${HOME_JS_LIMIT} B.`);
  if (problems.length) {
    console.error(problems.join('\n'));
    process.exit(1);
  }
  console.log(`Checked ${files.length} pages: links and SEO tags OK.`);
}
