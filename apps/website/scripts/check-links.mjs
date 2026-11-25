// Fails the build when a page in the built site links to a local page or file
// that does not exist, or is missing the SEO tags every page must carry.
import { readdirSync, readFileSync, existsSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';
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

export function isMain(moduleUrl, argvPath) {
  return Boolean(argvPath) && moduleUrl === pathToFileURL(argvPath).href;
}

if (isMain(import.meta.url, process.argv[1])) {
  const dist = process.argv[2] ?? 'dist';
  const files = htmlFiles(dist);
  const problems = files.flatMap((f) => checkPage(dist, f, readFileSync(f, 'utf8')));
  if (problems.length) {
    console.error(problems.join('\n'));
    process.exit(1);
  }
  console.log(`Checked ${files.length} pages: links and SEO tags OK.`);
}
