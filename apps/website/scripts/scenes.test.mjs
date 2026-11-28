import test from 'node:test';
import assert from 'node:assert/strict';
import { offlineFrame } from '../src/scripts/scenes/offline.mjs';
import { trainingFrame, tileFrame, restClock } from '../src/scripts/scenes/training.mjs';

// Every scene: p=1 is the finished state, the output depends only on p
// (same going down and up), and numeric vars stay finite and inside bounds.
function assertSceneContract(frameFn, finished, bounds = {}) {
  assert.deepEqual(frameFn(1), finished);
  const ps = Array.from({ length: 101 }, (_, i) => i / 100);
  const up = ps.map(p => frameFn(p));
  const down = [...ps].reverse().map(p => frameFn(p)).reverse();
  assert.deepEqual(up, down);
  for (const f of up) {
    for (const [k, v] of Object.entries(f.vars ?? {})) {
      assert.ok(Number.isFinite(v), `${k} finite`);
      const [lo, hi] = bounds[k] ?? [0, 1];
      assert.ok(v >= lo && v <= hi, `${k}=${v} within ${lo}..${hi}`);
    }
  }
}

test('offline scene follows the timeline', () => {
  assertSceneContract(offlineFrame,
    { vars: { bars: 4, sync: 1 }, attrs: { saved: '3', online: 'yes', point: '2' } },
    { bars: [0, 4] });
  const start = offlineFrame(0);
  assert.equal(start.vars.bars, 4);
  assert.equal(start.attrs.saved, '0');
  assert.equal(start.attrs.online, 'yes');
  const dead = offlineFrame(0.15);
  assert.equal(dead.vars.bars, 0);
  assert.equal(dead.attrs.online, 'no');
  assert.equal(offlineFrame(0.4).attrs.saved, '2');
  assert.equal(offlineFrame(0.66).attrs.online, 'no');
  assert.equal(offlineFrame(0.3).attrs.point, '0');
  assert.equal(offlineFrame(0.8).attrs.point, '1');
  assert.equal(offlineFrame(0.8).vars.sync > 0, true);
});

test('training scene steps through library, programs, log, rest and progress', () => {
  const desk = p => trainingFrame(p, { mobile: false });
  assertSceneContract(desk, {
    vars: { lib: 1, prog: 1, log: 1, ring: 1, bars: 1 },
    attrs: { step: '4', mode: 'pinned' },
    text: { '[data-kg]': '70', '[data-reps]': '6', '.timer-text b': '00:00' },
  });
  assert.equal(desk(0.1).attrs.step, '0');
  assert.equal(desk(0).text['[data-kg]'], '65');
  assert.equal(desk(0).text['[data-reps]'], '8');
  const mid = desk(0.5);
  assert.equal(mid.attrs.step, '2');
  const kg = Number(mid.text['[data-kg]']);
  assert.ok(kg >= 65 && kg <= 70);
  assert.match(desk(0.7).text['.timer-text b'], /^0[01]:\d\d$/);
  assert.equal(desk(0.8).attrs.step, '4');
  assert.equal(trainingFrame(0.5, { mobile: true }).attrs.mode, 'tiles');
  assert.deepEqual(trainingFrame(0.5, { mobile: false, short: true }).attrs, { mode: 'tiles' });
});
test('rest clock counts 01:30 down to 00:00', () => {
  assert.equal(restClock(0), '01:30');
  assert.equal(restClock(0.5), '00:45');
  assert.equal(restClock(1), '00:00');
});
test('tiles scrub on phones and sit finished elsewhere', () => {
  assert.deepEqual(tileFrame(1, { mobile: true }).vars, { k: 1 });
  assert.equal(tileFrame(0.25, { mobile: true }).vars.k, 0.25);
  assert.equal(tileFrame(0.25, { mobile: false }).vars.k, 1);
  assert.equal(tileFrame(0, { mobile: true }).text['[data-kg]'], '65');
  assert.equal(tileFrame(1, { mobile: true }).text['[data-kg]'], '70');
});
