import test from 'node:test';
import assert from 'node:assert/strict';
import { revealBelowFold } from '../src/scripts/home-motion.mjs';

function fixture({ reduced = false, supported = true } = {}) {
  const observed = new Set();
  const active = {};
  const target = (top, focused = false) => ({
    getBoundingClientRect: () => ({ top }),
    contains: (element) => focused && element === active,
    classes: [],
    classList: { add(name) { this.owner.classes.push(name); } },
  });
  const targets = [target(20), target(800), target(900, true), target(1000)];
  for (const item of targets) item.classList.owner = item;
  let callback;
  const doc = { querySelectorAll: () => targets, activeElement: active };
  const win = {
    innerHeight: 700,
    matchMedia: () => ({ matches: reduced }),
    IntersectionObserver: supported ? class {
      constructor(fn) { callback = fn; }
      observe(item) { observed.add(item); }
      unobserve(item) { observed.delete(item); }
    } : undefined,
  };
  return {
    doc, win, targets, observed,
    setReduced(value) { reduced = value; },
    intersect(item, isIntersecting = true) {
      callback([{ target: item, isIntersecting }]);
    },
  };
}

test('reveals below-fold targets once, without hiding visible or focused content', () => {
  const f = fixture();
  revealBelowFold(f.doc, f.win);
  const [visible, below, focused] = f.targets;
  assert.equal(f.observed.has(visible), false);
  assert.equal(f.observed.has(below), true);
  assert.deepEqual(below.classes, []);
  f.intersect(below, false);
  assert.equal(f.observed.has(below), true);
  f.intersect(below);
  assert.deepEqual(below.classes, ['home-reveal']);
  assert.equal(f.observed.has(below), false);
  f.intersect(focused);
  assert.deepEqual(focused.classes, []);
  assert.equal(f.observed.has(focused), false);
});

test('reduced motion and unsupported browsers keep the static page', () => {
  for (const options of [{ reduced: true }, { supported: false }]) {
    const f = fixture(options);
    revealBelowFold(f.doc, f.win);
    assert.equal(f.observed.size, 0);
    assert.ok(f.targets.every((target) => target.classes.length === 0));
  }
});

test('a preference change before intersection suppresses the reveal', () => {
  const f = fixture();
  revealBelowFold(f.doc, f.win);
  f.setReduced(true);
  const target = f.targets[3];
  f.intersect(target);
  assert.deepEqual(target.classes, []);
  assert.equal(f.observed.has(target), false);
});
