import test from 'node:test';
import assert from 'node:assert/strict';
import { backdropAllowed, paletteAt, renderSize, introCovers, mountBackdrop } from '../src/scripts/backdrop.mjs';

const ok = { motionOk: true, webgl: true };

test('backdropAllowed is true on a normal device', () => {
  assert.equal(backdropAllowed(ok), true);
  assert.equal(backdropAllowed({ ...ok, deviceMemory: undefined, hardwareConcurrency: 8 }), true);
  assert.equal(backdropAllowed({ ...ok, deviceMemory: 4, hardwareConcurrency: 4 }), true);
});
test('backdropAllowed is false for each guard', () => {
  assert.equal(backdropAllowed({ ...ok, motionOk: false }), false);
  assert.equal(backdropAllowed({ ...ok, webgl: false }), false);
  assert.equal(backdropAllowed({ ...ok, saveData: true }), false);
  assert.equal(backdropAllowed({ ...ok, deviceMemory: 2 }), false);
  assert.equal(backdropAllowed({ ...ok, hardwareConcurrency: 2 }), false);
});

const stops = [{ y: 0, color: [1, 0, 0] }, { y: 1000, color: [0, 0, 1] }];
test('paletteAt holds the exact colour until the blend zone', () => {
  assert.deepEqual(paletteAt(stops, 0), [1, 0, 0]);
  assert.deepEqual(paletteAt(stops, 600), [1, 0, 0]);
  assert.deepEqual(paletteAt(stops, -50), [1, 0, 0]);
  assert.deepEqual(paletteAt(stops, 1000), [0, 0, 1]);
  assert.deepEqual(paletteAt(stops, 5000), [0, 0, 1]);
});
test('paletteAt blends monotonically inside the last 30% of the gap', () => {
  const mid = paletteAt(stops, 850);
  assert.ok(mid[0] > 0 && mid[0] < 1 && mid[2] > 0 && mid[2] < 1);
  let prev = -1;
  for (let y = 700; y <= 1000; y += 10) {
    const b = paletteAt(stops, y)[2];
    assert.ok(b >= prev, `blue at ${y}`);
    prev = b;
  }
});
test('renderSize caps dpr at 1 and halves each axis', () => {
  assert.deepEqual(renderSize(1440, 900, 2), { w: 720, h: 450 });
  assert.deepEqual(renderSize(390, 844, 3), { w: 195, h: 422 });
  assert.deepEqual(renderSize(0, 0, 1), { w: 1, h: 1 });
});
test('introCovers while the viewport bottom is still inside the intro', () => {
  assert.equal(introCovers(0, 900, 4000), true);
  assert.equal(introCovers(3100, 900, 4000), true);
  assert.equal(introCovers(3200, 900, 4000), false);
  assert.equal(introCovers(0, 900, 0), false);
});

// ---- mount harness ----
function harness({ gl = true, motion = true } = {}) {
  const classes = new Set();
  const parent = { classList: { add: c => classes.add(c), remove: c => classes.delete(c), contains: c => classes.has(c) } };
  const canvasListeners = {};
  const fakeGl = new Proxy({}, {
    get: (t, k) => {
      if (k === 'getShaderParameter' || k === 'getProgramParameter') return () => true;
      if (k === 'isContextLost') return () => false;
      if (typeof k === 'string' && /^[A-Z_0-9]+$/.test(k)) return 1;
      return () => ({});
    },
  });
  const canvas = {
    parentElement: parent, width: 0, height: 0, style: {},
    getContext: () => (gl ? fakeGl : null),
    addEventListener: (t, f) => { (canvasListeners[t] ||= []).push(f); },
    removeEventListener: () => {},
  };
  let rafCount = 0, queue = [];
  const mq = { matches: motion, listeners: [], addEventListener(t, f) { this.listeners.push(f); }, removeEventListener() {} };
  const docListeners = {};
  const win = {
    innerWidth: 1440, innerHeight: 900, scrollY: 2000, devicePixelRatio: 2,
    navigator: {},
    document: {
      hidden: false,
      documentElement: {},
      querySelector: () => null,
      querySelectorAll: () => [],
      addEventListener: (t, f) => { (docListeners[t] ||= []).push(f); },
      removeEventListener: () => {},
    },
    getComputedStyle: () => ({ getPropertyValue: n => ({ '--lime': '#d6ff60', '--performance': '#316946', '--sleep': '#c1a9ff', '--hero-to': '#0d2225' }[n] ?? '') }),
    matchMedia: q => (q.includes('prefers-color-scheme') ? { matches: false, addEventListener() {}, removeEventListener() {} }
      : q.includes('pointer') ? { matches: false, addEventListener() {}, removeEventListener() {} } : mq),
    requestAnimationFrame: f => { rafCount++; queue.push(f); return rafCount; },
    cancelAnimationFrame: () => {},
    addEventListener: () => {}, removeEventListener: () => {},
    performance: { now: () => 0 },
  };
  const tick = (t = 16) => { const q = queue; queue = []; q.forEach(f => f(t)); };
  return { canvas, parent, win, mq, canvasListeners, rafs: () => rafCount, tick, docListeners };
}

test('mountBackdrop goes live after the first frame when WebGL works', () => {
  const h = harness();
  mountBackdrop(h.canvas, h.win);
  h.tick(); h.tick(100);
  assert.equal(h.parent.classList.contains('is-live'), true);
});
test('mountBackdrop falls back when there is no WebGL', () => {
  const h = harness({ gl: false });
  assert.doesNotThrow(() => mountBackdrop(h.canvas, h.win));
  h.tick();
  assert.equal(h.parent.classList.contains('is-live'), false);
});
test('mountBackdrop falls back on context loss', () => {
  const h = harness();
  mountBackdrop(h.canvas, h.win);
  h.tick(); h.tick(100);
  assert.equal(h.parent.classList.contains('is-live'), true);
  let prevented = false;
  h.canvasListeners.webglcontextlost.forEach(f => f({ preventDefault: () => { prevented = true; } }));
  assert.equal(prevented, true);
  assert.equal(h.parent.classList.contains('is-live'), false);
  const before = h.rafs();
  h.tick(200); h.tick(300);
  assert.equal(h.rafs(), before);
});
test('mountBackdrop stops when reduced motion turns on', () => {
  const h = harness();
  mountBackdrop(h.canvas, h.win);
  h.tick(); h.tick(100);
  h.mq.matches = false;
  h.mq.listeners.forEach(f => f({ matches: false }));
  assert.equal(h.parent.classList.contains('is-live'), false);
  const before = h.rafs();
  h.tick(200); h.tick(300);
  assert.equal(h.rafs(), before);
});
test('mountBackdrop falls back even if the reduced-motion event never arrives', () => {
  const h = harness();
  mountBackdrop(h.canvas, h.win);
  h.tick(); h.tick(100);
  assert.equal(h.parent.classList.contains('is-live'), true);
  h.mq.matches = false;
  h.tick(200); h.tick(300);
  assert.equal(h.parent.classList.contains('is-live'), false);
});
test('mountBackdrop does nothing without motion', () => {
  const h = harness({ motion: false });
  mountBackdrop(h.canvas, h.win);
  h.tick();
  assert.equal(h.rafs(), 0);
  assert.equal(h.parent.classList.contains('is-live'), false);
});
