import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { cinematicFrame, progressForScroll, settleFactor, setIfChanged, stackRank, introFits, stackReach, fitMobileStack, MAX_STACK_SIZE, MIN_STACK_SIZE, MOTION_QUERY } from '../src/scripts/home-motion.mjs';
import { countUpText, splitWords, magnetOffset } from '../src/scripts/home-reveal.mjs';

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
  assert.ok(Math.abs(settleFactor(1000/60) - .34) < 1e-9);
  assert.equal(settleFactor(0), 0);
  assert.ok(settleFactor(10000) > .999 && settleFactor(10000) <= 1);
});
test('the scene follows the scroll closely', () => {
  for (const hz of [60, 120]) {
    let current = 0;
    for (let i = 0; i < hz / 10; i++) current += (1 - current) * settleFactor(1000 / hz);
    assert.ok(current >= .9, `${hz} Hz covered ${current} after 100 ms`);
  }
});
test('scene copy and the progress meter get their own layer, only when motion is on', () => {
  const css = readFileSync(new URL('../src/styles/home-motion.css', import.meta.url), 'utf8');
  const at = css.indexOf('@media (prefers-reduced-motion: no-preference)');
  assert.ok(at > 0);
  const end = css.indexOf('\n@media (max-width: 720px)', at);
  assert.ok(end > at);
  const motion = css.slice(at, end);
  assert.match(motion, /\.motion-ready \.cine-scene \{[^}]*will-change: transform, opacity/);
  assert.match(motion, /\.cine-meter i \{[^}]*will-change: transform/);
  assert.equal(css.slice(0, at).includes('will-change'), false);
  assert.equal(css.slice(end).includes('will-change'), false);
});
const rankOf = rigs => stackRank(rigs.map(order => ({ order })));
test('stackRank ranks rigs 1..3 by order, ties going to the higher index', () => {
  assert.deepEqual(rankOf([10, 5, 10]), [2, 1, 3]);
  assert.deepEqual(rankOf([1, 2, 3]), [1, 2, 3]);
  assert.deepEqual(rankOf([7, 7, 7]), [1, 2, 3]);
});
test('the stacking rank changes rarely and always matches the order', () => {
  for (const [w, h] of [[1440, 900], [390, 844]]) {
    let prev, changes = 0;
    for (let i = 0; i <= 1000; i++) {
      const { rigs } = cinematicFrame(i / 1000, w, h);
      const rank = stackRank(rigs);
      const sorted = rigs.map((r, j) => [r.order, j]).sort((a, b) => a[0] - b[0] || a[1] - b[1]).map(x => x[1]);
      assert.deepEqual(sorted.map(j => rank[j]), [1, 2, 3]);
      if (prev && prev.join() !== rank.join()) changes++;
      prev = rank;
    }
    assert.ok(changes <= 6, `${w}x${h}: ${changes} rank changes`);
  }
  for (const p of [0, .5, 1]) {
    const f = cinematicFrame(p, 1440, 900);
    assert.equal(f.rigs[f.active].opacity, 1);
    assert.equal(stackRank(f.rigs)[f.active], 3);
  }
});
test('setIfChanged writes a style value only when it differs from the last one written', () => {
  const cache = new Map(), el = {}, other = {}, writes = [];
  const write = v => writes.push(v);
  assert.equal(setIfChanged(cache, el, 'opacity', '1', write), true);
  assert.equal(setIfChanged(cache, el, 'opacity', '1', write), false);
  assert.equal(setIfChanged(cache, el, 'transform', '1', write), true);
  assert.equal(setIfChanged(cache, other, 'opacity', '1', write), true);
  assert.equal(setIfChanged(cache, el, 'opacity', '0', write), true);
  assert.equal(setIfChanged(cache, el, 'opacity', '1', write), true);
  assert.equal(writes.length, 5);
  cache.clear();
  assert.equal(setIfChanged(cache, el, 'opacity', '1', write), true);
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
// Independent projection: a rig is a 240x468 card; CSS applies the transform list
// right to left, so a corner is scaled, then rotated by Z, Y, X (one composed
// matrix Rx*Ry*Rz), translated and perspective-projected (1200px) about the centre.
const rad = d => d * Math.PI / 180;
const mul = (A, B) => A.map((_, i) => B[0].map((_, j) => A[i].reduce((s, _, k) => s + A[i][k] * B[k][j], 0)));
const Rx = a => [[1,0,0],[0,Math.cos(a),-Math.sin(a)],[0,Math.sin(a),Math.cos(a)]];
const Ry = a => [[Math.cos(a),0,Math.sin(a)],[0,1,0],[-Math.sin(a),0,Math.cos(a)]];
const Rz = a => [[Math.cos(a),-Math.sin(a),0],[Math.sin(a),Math.cos(a),0],[0,0,1]];
const extent = (r, center) => {
  const M = mul(mul(Rx(rad(r.rx)), Ry(rad(r.ry))), Rz(rad(r.ry * .22)));
  const ys = [[-120,-234],[120,-234],[-120,234],[120,234]].map(([cx, cy]) => {
    const v = [cx * r.scale, cy * r.scale, 0];
    const y = M[1][0]*v[0] + M[1][1]*v[1] + r.y;
    const z = M[2][0]*v[0] + M[2][1]*v[1] + r.z;
    return center + y * 1200 / (1200 - z);
  });
  return [Math.min(...ys), Math.max(...ys)];
};
const GAP = 12, DRIFT = 13;
const fitFor = (w, copyBottom, labelTop) =>
  fitMobileStack({ top: copyBottom + GAP + DRIFT, bottom: labelTop - GAP, max: Math.min(MAX_STACK_SIZE, w / 550) });
const minSlack = (w, h, copyBottom, labelTop, { center, size }) => {
  let slack = Infinity;
  for (let i = 0; i <= 240; i++) for (const r of cinematicFrame(i/240, w, h, size).rigs) {
    const [t, b] = extent(r, center);
    slack = Math.min(slack, t - (copyBottom + GAP + DRIFT), labelTop - GAP - b);
  }
  return slack;
};
test('the fitted phone stack stays between the copy and the label in every frame', () => {
  let fitted = 0;
  for (const [w, h, copyBottom, labelTop] of [[393,656,301,566],[390,844,360,755],[320,900,330,811],[430,932,380,843],[360,740,320,650],[375,667,300,577]]) {
    const fit = fitFor(w, copyBottom, labelTop);
    if (fit.size < MIN_STACK_SIZE) continue;
    fitted++;
    const slack = minSlack(w, h, copyBottom, labelTop, fit);
    assert.ok(slack >= -.01, `${w}x${h} slack ${slack}`);
  }
  assert.ok(fitted >= 4);
});
test('the fitted stack never exceeds the screen width cap', () => {
  const { size } = fitMobileStack({ top: 355, bottom: 799, max: Math.min(MAX_STACK_SIZE, 320 / 550) });
  assert.ok(size <= 320 / 550);
  assert.ok(size > 0);
  assert.equal(fitMobileStack({ top: 0, bottom: 5000 }).size, MAX_STACK_SIZE);
});
test('the old fixed placement overlaps the copy on a 393x656 phone, the fitted one does not', () => {
  const front = cinematicFrame(0, 393, 656).rigs[0];
  assert.ok(extent(front, 656 * .65)[0] < 301 + GAP);
  const fit = fitFor(393, 301, 566);
  assert.ok(extent(cinematicFrame(0, 393, 656, fit.size).rigs[0], fit.center)[0] >= 301 + GAP);
});
test('cinematicFrame without a size keeps the original sizing', () => {
  assert.equal(cinematicFrame(0,1440,900).rigs[0].scale, 1.13 * Math.min(1.17, 1440/1150, 900/720));
  assert.equal(cinematicFrame(0,390,844).rigs[0].scale, 1.13 * Math.min(MAX_STACK_SIZE, 390/550, 844/1130));
  assert.equal(cinematicFrame(0,390,844,.5).rigs[0].scale, 1.13 * .5);
});
test('stack reach is finite and positive and grows with size', () => {
  const a = stackReach(.4), b = stackReach(.6);
  assert.ok([a.up, a.down].every(n => Number.isFinite(n) && n > 0));
  assert.ok(b.up > a.up && b.down > a.down);
});
test('a band too small for the phones gives a size below the minimum', () => {
  assert.ok(fitMobileStack({ top: 300, bottom: 420 }).size < MIN_STACK_SIZE);
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

test('splitWords keeps punctuation attached and ignores extra spaces', () => {
  const words = splitWords('Plan it, lift it, see it add up');
  assert.equal(words.length, 8);
  assert.ok(words.includes('it,'));
  assert.deepEqual(splitWords('  a  b '), ['a', 'b']);
  assert.deepEqual(splitWords(''), []);
});
test('magnetOffset leans toward the pointer, never outside the radius', () => {
  assert.deepEqual(magnetOffset(200, 0, 120, 8), { x: 0, y: 0 });
  assert.deepEqual(magnetOffset(0, 0, 120, 8), { x: 0, y: 0 });
  const near = magnetOffset(60, 0, 120, 8);
  assert.ok(near.x > 0 && near.x <= 8);
  assert.equal(near.y, 0);
  const left = magnetOffset(-30, -30, 120, 8);
  assert.ok(left.x < 0 && left.y < 0);
  for (let d = 0; d <= 130; d += 5) {
    const o = magnetOffset(d, 0, 120, 8);
    assert.ok(Math.abs(o.x) <= 8 && Number.isFinite(o.x));
  }
});
