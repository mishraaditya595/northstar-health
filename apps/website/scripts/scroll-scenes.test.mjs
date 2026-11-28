import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { sceneProgress, crossProgress, seg, mountScenes } from '../src/scripts/scroll-scenes.mjs';

test('sceneProgress clamps to the track and never returns NaN', () => {
  assert.equal(sceneProgress(100, 2200, 1000), 0);
  assert.equal(sceneProgress(-600, 2200, 1000), 0.5);
  assert.equal(sceneProgress(-1200, 2200, 1000), 1);
  assert.equal(sceneProgress(-5000, 2200, 1000), 1);
  assert.equal(sceneProgress(0, 500, 1000), 0);
});
test('seg gives local progress inside a window', () => {
  assert.equal(seg(0.5, 0.4, 0.6), 0.5);
  assert.equal(seg(0.1, 0.4, 0.6), 0);
  assert.equal(seg(0.9, 0.4, 0.6), 1);
});
test('crossProgress runs 0 to 1 as a small block crosses the screen', () => {
  assert.equal(crossProgress(900, 300, 1000), 0);
  assert.equal(crossProgress(-300, 300, 1000), 1);
  const mid = crossProgress(500, 300, 1000);
  assert.ok(mid > 0 && mid < 1);
});

function el(extra = {}) {
  const style = { props: {}, setProperty(k, v) { this.props[k] = v; }, removeProperty(k) { delete this.props[k]; } };
  return { style, dataset: {}, children: {}, querySelector(sel) { return this.children[sel] ?? null; }, ...extra };
}
function setup({ top = -600, height = 2200, motion = true, width = 1440, io = true, name = 'x', mode } = {}) {
  const track = el({ getBoundingClientRect: () => ({ top, height, bottom: top + height }) });
  track.dataset.sceneTrack = name;
  if (mode) track.dataset.sceneMode = mode;
  const stage = el();
  track.children['[data-scene-stage]'] = stage;
  const label = el({ textContent: 'orig' });
  track.children['.label'] = label;
  const rootClasses = new Set();
  const doc = {
    documentElement: { classList: { add: c => rootClasses.add(c), remove: c => rootClasses.delete(c), contains: c => rootClasses.has(c) } },
    querySelectorAll: () => [track],
  };
  const mq = { matches: motion, listeners: [], addEventListener(t, f) { this.listeners.push(f); }, removeEventListener() {} };
  const listeners = {};
  let queue = [], rafCalls = 0;
  const ioInstances = [];
  const win = {
    innerHeight: 1000, innerWidth: width, scrollY: 0,
    matchMedia: () => mq,
    requestAnimationFrame: f => { rafCalls++; queue.push(f); return rafCalls; },
    cancelAnimationFrame: () => { queue = []; },
    addEventListener: (t, f) => { (listeners[t] ||= []).push(f); },
    removeEventListener: () => {},
  };
  if (io) {
    win.IntersectionObserver = class {
      constructor(cb) { this.cb = cb; ioInstances.push(this); }
      observe(t) { this.cb([{ target: t, isIntersecting: true }]); }
      unobserve() {} disconnect() {}
    };
  }
  const tick = () => { const q = queue; queue = []; q.forEach(f => f(16)); };
  return { track, label, doc, win, mq, rootClasses, tick, listeners, rafs: () => rafCalls, ioInstances, rect: v => Object.assign(v, {}) };
}

test('mountScenes applies the current progress on first frame', () => {
  const h = setup();
  const seen = [];
  mountScenes(h.doc, h.win, { x: p => { seen.push(p); return { vars: { x: p } }; } });
  h.tick();
  assert.equal(seen.at(-1), 0.5);
  assert.equal(h.track.style.props['--x'], '0.5');
  assert.equal(h.rootClasses.has('scenes-ready'), true);
});
test('mountScenes does nothing without motion', () => {
  const h = setup({ motion: false });
  let called = 0;
  mountScenes(h.doc, h.win, { x: () => { called++; return {}; } });
  h.tick();
  assert.equal(called, 0);
  assert.equal(h.rootClasses.has('scenes-ready'), false);
});
test('mountScenes does nothing without IntersectionObserver', () => {
  const h = setup({ io: false });
  mountScenes(h.doc, h.win, { x: () => ({}) });
  assert.equal(h.rootClasses.has('scenes-ready'), false);
});
test('snaps to the finished state when reduced motion turns on', () => {
  const h = setup();
  mountScenes(h.doc, h.win, { x: p => ({ vars: { x: p }, attrs: { step: '2' }, text: { '.label': 'changed' } }) });
  h.tick();
  assert.equal(h.label.textContent, 'changed');
  h.mq.matches = false;
  h.mq.listeners.forEach(f => f({ matches: false }));
  assert.equal(h.rootClasses.has('scenes-ready'), false);
  assert.deepEqual(h.track.style.props, {});
  assert.equal(h.track.dataset.step, undefined);
  assert.equal(h.label.textContent, 'orig');
  const before = h.rafs();
  (h.listeners.scroll || []).forEach(f => f());
  assert.equal(h.rafs(), before);
});
test('re-measures on resize', () => {
  const h = setup();
  const ctxs = [];
  mountScenes(h.doc, h.win, { x: (p, ctx) => { ctxs.push(ctx.mobile); return {}; } });
  h.tick();
  assert.equal(ctxs.at(-1), false);
  h.win.innerWidth = 390;
  h.listeners.resize.forEach(f => f());
  h.tick();
  assert.equal(ctxs.at(-1), true);
});
test('writes text and does not rewrite unchanged values', () => {
  const h = setup();
  let writes = 0;
  h.track.style.setProperty = function (k, v) { writes++; this.props[k] = v; };
  mountScenes(h.doc, h.win, { x: () => ({ vars: { a: 1 }, text: { '.label': '70' } }) });
  h.tick();
  assert.equal(h.label.textContent, '70');
  h.listeners.scroll.forEach(f => f()); h.tick();
  assert.equal(writes, 1);
});
test('only loops while a track is visible', () => {
  const h = setup();
  mountScenes(h.doc, h.win, { x: () => ({}) });
  h.tick();
  h.ioInstances[0].cb([{ target: h.track, isIntersecting: false }]);
  h.tick();
  const before = h.rafs();
  h.listeners.scroll.forEach(f => f());
  assert.equal(h.rafs(), before);
});
test('a track that scrolled past while hidden gets its finished state', () => {
  const h = setup({ top: -5000 });
  const seen = [];
  mountScenes(h.doc, h.win, { x: p => { seen.push(p); return {}; } });
  h.ioInstances[0].cb([{ target: h.track, isIntersecting: false }]);
  h.tick();
  assert.equal(seen.at(-1), 1);
});
test('cross mode uses the crossing progress', () => {
  const h = setup({ top: -300, height: 300, mode: 'cross' });
  const seen = [];
  mountScenes(h.doc, h.win, { x: p => { seen.push(p); return {}; } });
  h.tick();
  assert.equal(seen.at(-1), 1);
});

test('scene CSS only sticks and sizes tracks under .scenes-ready in the motion media query', () => {
  const css = readFileSync(new URL('../src/styles/home-scenes.css', import.meta.url), 'utf8');
  const at = css.indexOf('@media (prefers-reduced-motion: no-preference)');
  assert.ok(at >= 0, 'has a no-preference media block');
  const outside = css.slice(0, at);
  assert.doesNotMatch(outside, /position:\s*sticky/);
  assert.doesNotMatch(outside, /--track/);
  const inside = css.slice(at);
  const rules = [...inside.matchAll(/([^{}]+)\{([^{}]*)\}/g)];
  for (const [, sel, body] of rules) {
    if (/position:\s*sticky|--track|height:\s*var\(--track/.test(body)) {
      assert.match(sel, /\.scenes-ready/, `rule "${sel.trim()}" must sit under .scenes-ready`);
    }
  }
});
