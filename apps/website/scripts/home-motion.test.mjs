import test from 'node:test';
import assert from 'node:assert/strict';
import { cinematicFrame, progressForScroll } from '../src/scripts/home-motion.mjs';

test('scroll progress is clamped to the pinned track', () => {
  assert.equal(progressForScroll(50,3600,1000),0);
  assert.equal(progressForScroll(-1300,3600,1000),.5);
  assert.equal(progressForScroll(-2600,3600,1000),1);
  assert.equal(progressForScroll(-3000,3600,1000),1);
});
test('the active phone and copy match every chapter at desktop and mobile widths', () => {
  for (const width of [320,390,1440]) {
    for (const i of [0,1,2]) {
      const f = cinematicFrame(i/2,width,844);
      assert.equal(f.active,i);
      assert.equal(f.scenes[i].opacity,1);
      assert.equal(f.rigs[i].opacity,1);
      assert.equal(f.rigs[i].x,0);
      assert.ok(f.rigs.every(r => Number.isFinite(r.scale) && r.scale>0));
      assert.ok(f.rigs.every((r,j) => j===i || r.order<f.rigs[i].order));
      assert.ok(f.scenes.every((s,j) => j===i || s.opacity===0));
    }
  }
});
test('interpolation is deterministic, reversible and bounded', () => {
  const checkpoints = Array.from({length:101},(_,i)=>i/100);
  const forward = checkpoints.map(p=>cinematicFrame(p,1440,900));
  assert.deepEqual([...checkpoints].reverse().map(p=>cinematicFrame(p,1440,900)),[...forward].reverse());
  for (const frame of forward) {
    assert.ok(frame.rigs.every(r=>r.opacity>=0 && r.opacity<=1));
    assert.ok(frame.scenes.filter(s=>s.opacity>.5).length<=1);
  }
});
