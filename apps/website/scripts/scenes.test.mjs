import test from 'node:test';
import assert from 'node:assert/strict';
import { offlineFrame } from '../src/scripts/scenes/offline.mjs';

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
