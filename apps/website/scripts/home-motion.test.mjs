import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { cinematicFrame, progressForScroll, settleFactor, introFits, MOTION_QUERY } from '../src/scripts/home-motion.mjs';
import { countUpText } from '../src/scripts/home-reveal.mjs';

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

test('settling covers the same distance per second at 60 Hz and 120 Hz', () => {
  const at60 = 1 - settleFactor(1000/60);
  const at120 = 1 - settleFactor(1000/120);
  assert.ok(Math.abs(at60 - at120*at120) < 1e-9);
  assert.ok(Math.abs(settleFactor(1000/60) - .16) < 1e-9);
  assert.equal(settleFactor(0), 0);
  assert.ok(settleFactor(10000) > .999 && settleFactor(10000) <= 1);
});
test('the pinned intro only runs when every chapter clears the nav and the chapter bar', () => {
  const desktop = { stageHeight: 900, navHeight: 92, bottomHeight: 94, mobile: false };
  assert.equal(introFits({ ...desktop, sceneHeights: [520,500,560] }), true);
  // Centred copy taller than the space between the bars would overlap them.
  assert.equal(introFits({ ...desktop, sceneHeights: [520,500,720] }), false);
  assert.equal(introFits({ ...desktop, stageHeight: 620, sceneHeights: [430,400,430] }), false);
  const phone = { stageHeight: 844, navHeight: 76, bottomHeight: 70, mobile: true };
  assert.equal(introFits({ ...phone, sceneHeights: [300,260,310] }), true);
  assert.equal(introFits({ ...phone, sceneHeights: [300,260,420] }), false);
  // Enlarged text makes the nav taller than the gap above the phone copy.
  assert.equal(introFits({ ...phone, navHeight: 130, sceneHeights: [300,260,310] }), false);
});
test('count-up text starts at zero, ends on the exact value and keeps its format', () => {
  assert.equal(countUpText('6,240', 0), '0');
  assert.equal(countUpText('6,240', 1), '6,240');
  assert.equal(countUpText('6,240', .5), '3,120');
  assert.equal(countUpText('74.2', 1), '74.2');
  assert.equal(countUpText('74.2', .5), '37.1');
  assert.equal(countUpText('58', .25), '15');
  assert.equal(countUpText('7h 24m', .5), '7h 24m');
});
test('the pre-paint layout check uses the same media query as the script', () => {
  const astro = readFileSync(new URL('../src/components/CinematicIntro.astro', import.meta.url), 'utf8');
  assert.ok(astro.includes(`matchMedia('${MOTION_QUERY}')`));
});
