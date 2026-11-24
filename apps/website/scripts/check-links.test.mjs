import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { checkPage, isMain } from './check-links.mjs';
import { pathToFileURL } from 'node:url';

const head =
  '<title>t</title><meta name="description" content="d"><link rel="canonical" href="x">' +
  '<meta property="og:image" content="x"><script type="application/ld+json">{}</script>';

function site() {
  const dist = mkdtempSync(join(tmpdir(), 'site-'));
  writeFileSync(join(dist, 'index.html'), '');
  writeFileSync(join(dist, 'privacy.html'), '');
  writeFileSync(join(dist, 'favicon.svg'), '');
  return dist;
}

test('accepts clean URLs that map to .html files and existing assets', () => {
  const dist = site();
  const html = `${head}<a href="/">h</a><a href="/privacy">p</a><a href="/privacy#x">p</a><img src="/favicon.svg">`;
  assert.deepEqual(checkPage(dist, join(dist, 'index.html'), html), []);
});

test('ignores external links', () => {
  const dist = site();
  const html = `${head}<a href="https://example.com/nope">e</a><a href="mailto:a@b.c">m</a>`;
  assert.deepEqual(checkPage(dist, join(dist, 'index.html'), html), []);
});

test('reports a broken local link', () => {
  const dist = site();
  const problems = checkPage(dist, join(dist, 'index.html'), `${head}<a href="/terms">t</a>`);
  assert.deepEqual(problems, ['index.html: broken local link /terms']);
});

test('reports missing SEO tags', () => {
  const dist = site();
  const problems = checkPage(dist, join(dist, 'index.html'), '<title>t</title>');
  assert.equal(problems.length, 4);
  assert.ok(problems.includes('index.html: missing rel="canonical"'));
});

test('a noindex page needs no canonical but must not carry one', () => {
  const dist = site();
  const base = '<title>t</title><meta name="description" content="d"><meta name="robots" content="noindex">' +
    '<meta property="og:image" content="x"><script type="application/ld+json">{}</script>';
  assert.deepEqual(checkPage(dist, join(dist, 'index.html'), base), []);
  assert.deepEqual(checkPage(dist, join(dist, 'index.html'), `${base}<link rel="canonical" href="x">`), [
    'index.html: noindex page has a canonical link',
  ]);
});

test('runs as a script even when its path contains a space', () => {
  const path = '/tmp/my site/scripts/check-links.mjs';
  assert.equal(isMain(pathToFileURL(path).href, path), true);
  assert.equal(isMain(pathToFileURL(path).href, '/tmp/other.mjs'), false);
});
