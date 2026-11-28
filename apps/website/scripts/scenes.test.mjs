import test from 'node:test';
import assert from 'node:assert/strict';
import { offlineFrame } from '../src/scripts/scenes/offline.mjs';
import { privacyFrame, startOffsets } from '../src/scripts/scenes/privacy.mjs';
import { recoveryFrame } from '../src/scripts/scenes/recovery.mjs';
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

test('recovery scene draws the wave, sweeps the gauge, then counts up', () => {
  assertSceneContract(recoveryFrame, {
    vars: { wave: 1, energy: 1, trend: 1 },
    text: { '[data-energy-value]': '74', '[data-steps]': '6,240', '[data-rhr]': '58' },
  });
  const start = recoveryFrame(0);
  assert.deepEqual(start.text, { '[data-energy-value]': '0', '[data-steps]': '0', '[data-rhr]': '0' });
  assert.deepEqual(start.vars, { wave: 0, energy: 0, trend: 0 });
  for (let i = 0; i <= 100; i++) {
    const t = recoveryFrame(i / 100).text;
    assert.ok(Number(t['[data-energy-value]']) <= 74);
    assert.ok(Number(t['[data-steps]'].replace(',', '')) <= 6240);
    assert.ok(Number(t['[data-rhr]']) <= 58);
  }
});

test('privacy scene splits the data, then locks the phone card', () => {
  assertSceneContract(privacyFrame, { vars: { split: 1 }, attrs: { locked: 'yes' } });
  assert.equal(privacyFrame(0).vars.split, 0);
  assert.equal(privacyFrame(0.5).attrs.locked, 'no');
  assert.equal(privacyFrame(0.75).attrs.locked, 'yes');
});
test('startOffsets pile every item at the centre, stacked in order', () => {
  const rects = [{ x: 0, y: 0, w: 100, h: 20 }, { x: 0, y: 40, w: 100, h: 20 }, { x: 300, y: 0, w: 100, h: 20 }];
  const centre = { x: 0, y: 0, w: 400, h: 200 };
  const o = startOffsets(rects, centre, 30);
  assert.equal(o.length, 3);
  // Item centres (50,10), (50,50), (350,10) move to x=200, and stack 30px apart around y=100.
  assert.deepEqual(o[0], { fx: 150, fy: 100 - 30 - 10 });
  assert.deepEqual(o[1], { fx: 150, fy: 100 - 50 });
  assert.deepEqual(o[2], { fx: -150, fy: 100 + 30 - 10 });
});
