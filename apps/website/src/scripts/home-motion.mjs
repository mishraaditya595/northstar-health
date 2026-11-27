// Three approved product poses, interpolated by native page scroll.
// No video seeks, animation libraries, scroll interception or idle RAF loop.
const poses = [
  [[0,0,30,-8,-12,1.13,1],[-175,40,-130,8,22,.86,.65],[165,65,-170,-9,-27,.77,.38]],
  [[170,32,-130,-8,-28,.82,.62],[0,0,55,0,-3,1.18,1],[-175,55,-160,8,30,.78,.48]],
  [[-175,50,-175,8,27,.78,.45],[170,32,-115,-7,-24,.85,.68],[0,0,65,-3,-8,1.18,1]],
];
const clamp = (n, a = 0, b = 1) => Math.max(a, Math.min(b, n));
const mix = (a, b, t) => a + (b - a) * t;
const smooth = t => t * t * (3 - 2 * t);

export function progressForScroll(top, trackHeight, stageHeight) {
  return clamp(-top / Math.max(1, trackHeight - stageHeight));
}

// `fixedSize` lets the phone layout shrink the stack to fit its free band.
export function cinematicFrame(progress, width, height, fixedSize) {
  const p = clamp(progress);
  const mobile = width <= 720;
  const size = fixedSize ?? (mobile ? Math.min(MAX_STACK_SIZE, width / 550, height / 1130)
    : Math.min(1.17, width / 1150, height / 720));
  const q = p * 2;
  const segment = Math.min(1, Math.floor(q));
  const t = smooth(clamp(q - segment));
  const active = Math.min(2, Math.round(q));
  return {
    active,
    rigs: poses[segment].map((pose, i) => {
      const [x,y,z,rx,ry,s,o] = pose.map((n,j) => mix(n, poses[segment+1][i][j], t));
      return { x:x*size, y:(y+Math.sin(t*Math.PI)*28)*size, z:z*size, rx, ry, scale:s*size, opacity:o, order:Math.round(z+200) };
    }),
    scenes: poses.map((_,i) => ({
      opacity: 1 - smooth(clamp((Math.abs(q-i)-.2)/.32)),
      drift: (i-q)*(mobile?25:48),
    })),
    mobile,
  };
}

// Share of the remaining distance covered in one frame, scaled so a 120 Hz
// screen settles in the same time as a 60 Hz one.
export function settleFactor(dtMs, base = .16) {
  return 1 - Math.pow(1 - base, clamp(dtMs, 0, 1000) / (1000 / 60));
}

// The pinned intro needs every chapter's copy to fit without overlapping the
// nav or the chapter bar. Desktop copy is centred; phone copy sits above the
// phones and gets the top 43% of the stage.
export function introFits({ sceneHeights, stageHeight, navHeight, bottomHeight, mobile }) {
  // Phone copy starts at 12% of the stage, so the nav must end above that.
  if (mobile && navHeight > stageHeight * .12) return false;
  const room = mobile ? stageHeight * .43
    : stageHeight - 2 * Math.max(navHeight, bottomHeight) - 16;
  return sceneHeights.every(h => h <= room);
}

// These must match home-motion.css: .cine-visual perspective and .cine-rig size.
const PERSPECTIVE = 1200, RIG_W = 240, RIG_H = 468;
export const MAX_STACK_SIZE = .69;
export const MIN_STACK_SIZE = .3;
// Scenes drift 25px per chapter while visible (opacity window .2 + .32).
const SCENE_DRIFT = 25 * .52, STACK_GAP = 12;

// Vertical extent of a rig's projected corners, as offsets from the stack
// centre. CSS applies the transform list right to left: scale, rotateZ,
// rotateY, rotateX, translate3d, then the perspective divide.
export function rigExtent(r) {
  const [cz, sz] = [Math.cos(r.ry * .22 * Math.PI / 180), Math.sin(r.ry * .22 * Math.PI / 180)];
  const [cy, sy] = [Math.cos(r.ry * Math.PI / 180), Math.sin(r.ry * Math.PI / 180)];
  const [cx, sx] = [Math.cos(r.rx * Math.PI / 180), Math.sin(r.rx * Math.PI / 180)];
  let top = Infinity, bottom = -Infinity;
  for (const [u, v] of [[-1,-1],[1,-1],[-1,1],[1,1]]) {
    const x0 = u * RIG_W / 2 * r.scale, y0 = v * RIG_H / 2 * r.scale;
    const x1 = x0 * cz - y0 * sz, y1 = x0 * sz + y0 * cz;
    const z2 = -x1 * sy;
    const y3 = y1 * cx - z2 * sx, z3 = y1 * sx + z2 * cx;
    const y = (y3 + r.y) * PERSPECTIVE / (PERSPECTIVE - (z3 + r.z));
    top = Math.min(top, y); bottom = Math.max(bottom, y);
  }
  return { top, bottom };
}

// Farthest the stack reaches above (up) and below (down) its centre at this
// size, in px, over every frame.
export function stackReach(size) {
  let up = 0, down = 0;
  for (let i = 0; i <= 240; i++) {
    for (const r of cinematicFrame(i / 240, 0, 0, size).rigs) {
      const { top, bottom } = rigExtent(r);
      up = Math.max(up, -top); down = Math.max(down, bottom);
    }
  }
  return { up, down };
}

// Fit the stack into the free band [top, bottom] (px from the stage top): the
// largest size up to `max` whose reach (plus a 2% margin) fits, centred in the
// slack. Reach is not linear in size (perspective), so bisect.
export function fitMobileStack({ top, bottom, max = MAX_STACK_SIZE }) {
  const band = bottom - top;
  const reach = size => {
    const { up, down } = stackReach(size);
    return { up: up * 1.02, down: down * 1.02 };
  };
  const fits = size => { const r = reach(size); return r.up + r.down <= band; };
  let size = max;
  if (!fits(max)) {
    let lo = 0, hi = max;
    for (let i = 0; i < 20; i++) { const mid = (lo + hi) / 2; if (fits(mid)) lo = mid; else hi = mid; }
    size = lo;
  }
  const { up, down } = reach(size);
  return { size, center: top + up + (band - up - down) / 2 };
}

export const MOTION_QUERY = '(prefers-reduced-motion: no-preference) and (min-height: 581px)';

export function mountCinematic(root, win) {
  const doc = root.ownerDocument;
  const stage = root.querySelector('[data-stage]');
  const word = root.querySelector('[data-word]');
  const nav = root.querySelector('.cine-nav');
  const bottom = root.querySelector('.cine-bottom');
  const label = root.querySelector('.cine-label');
  const scenes = [...root.querySelectorAll('[data-scene]')];
  const rigs = [...root.querySelectorAll('[data-rig]')];
  const buttons = [...root.querySelectorAll('[data-chapter]')];
  const progressEls = [...root.querySelectorAll('[data-progress]')];
  if (!stage || !word || !nav || !bottom || !label || scenes.length !== 3 || rigs.length !== 3 ||
      buttons.length !== 3 || !win.matchMedia || !win.requestAnimationFrame) {
    root.classList.remove('motion-ready');
    return;
  }
  const media = win.matchMedia(MOTION_QUERY);
  let current = 0, target = 0, raf = 0, last = 0, enabled = false, active = -1;
  // Layout is measured in reset() only, so scrolling never forces a reflow.
  let trackTop = 0, travel = 1, width = win.innerWidth, height = win.innerHeight;
  let focusAfterSettle = -1;
  // Phone stack size fitted between the copy and the label; undefined = default.
  let stackSize;
  // Chapter in view while the static layout shows, read before a resize
  // reflows the page so the reader's place survives a layout switch.
  let staticCh = -1, staticRaf = 0;

  function setActive(i) {
    if (i === active) return;
    active = i;
    word.textContent = ['REP.', 'LIFT.', 'REST.'][i];
    buttons.forEach((b, j) => {
      if (j === i) b.setAttribute('aria-current', 'step');
      else b.removeAttribute('aria-current');
    });
    scenes.forEach((el, j) => el.classList.toggle('is-active', j === i));
  }
  function draw(p) {
    const frame = cinematicFrame(p, width, height, stackSize);
    progressEls.forEach(el => el.style.setProperty('--p', p.toFixed(4)));
    rigs.forEach((el, i) => {
      const v = frame.rigs[i];
      el.style.transform = `translate(-50%,-50%) translate3d(${v.x}px,${v.y}px,${v.z}px) rotateX(${v.rx}deg) rotateY(${v.ry}deg) rotateZ(${v.ry * .22}deg) scale(${v.scale})`;
      el.style.opacity = String(v.opacity);
      el.style.zIndex = String(v.order);
    });
    scenes.forEach((el, i) => {
      const v = frame.scenes[i];
      el.style.opacity = String(v.opacity);
      el.style.transform = frame.mobile ? `translateY(${v.drift}px)` : `translateY(calc(-50% + ${v.drift}px))`;
    });
    setActive(frame.active);
  }
  function loop(now) {
    raf = 0;
    if (!enabled) return;
    const dt = last ? now - last : 1000 / 60;
    last = now;
    current += (target - current) * settleFactor(dt);
    if (Math.abs(target - current) < .001) current = target;
    draw(current);
    if (current !== target) { raf = win.requestAnimationFrame(loop); return; }
    last = 0;
    if (focusAfterSettle >= 0 && focusAfterSettle === active) {
      const heading = scenes[focusAfterSettle].querySelector('h1, h2');
      focusAfterSettle = -1;
      heading?.focus({ preventScroll: true });
    }
  }
  function read() {
    if (!enabled) {
      if (!staticRaf) staticRaf = win.requestAnimationFrame(() => { staticRaf = 0; staticCh = staticChapter(); });
      return;
    }
    target = clamp((win.scrollY - trackTop) / travel);
    if (!raf) raf = win.requestAnimationFrame(loop);
  }
  function scrollToChapter(i, behavior) {
    win.scrollTo({ top: trackTop + travel * i / 2, behavior });
  }
  function clearStyles() {
    stackSize = undefined;
    stage.style.removeProperty('--cine-stack-y');
    scenes.forEach(el => {
      el.style.removeProperty('opacity');
      el.style.removeProperty('transform');
      el.classList.remove('is-active');
    });
  }
  function measure() {
    width = win.innerWidth;
    height = win.innerHeight;
    trackTop = root.getBoundingClientRect().top + win.scrollY;
    travel = Math.max(1, root.offsetHeight - stage.offsetHeight);
  }
  // In the static layout, the last chapter whose text starts in the top 40%
  // of the screen, or -1 when the intro is off screen.
  function staticChapter() {
    const rootBox = root.getBoundingClientRect();
    if (rootBox.bottom < 0 || rootBox.top > win.innerHeight) return -1;
    let best = 0;
    scenes.forEach((el, i) => {
      if (el.getBoundingClientRect().top <= win.innerHeight * .4) best = i;
    });
    return best;
  }
  function reset() {
    // Remember which chapter the reader was on, so rotating a phone or
    // zooming keeps it in view whichever layout comes next.
    const wasEnabled = enabled;
    const wasInside = wasEnabled ? win.scrollY >= trackTop && win.scrollY < trackTop + travel
      : staticCh > 0;
    const chapter = wasEnabled ? Math.round(clamp((win.scrollY - trackTop) / travel) * 2)
      : Math.max(0, staticCh);
    enabled = false;
    if (raf) win.cancelAnimationFrame(raf);
    raf = 0; last = 0; active = -1;
    clearStyles();
    root.classList.toggle('motion-ready', media.matches);
    const mobile = win.innerWidth <= 720;
    let ok = media.matches && introFits({
      sceneHeights: scenes.map(el => el.offsetHeight),
      stageHeight: stage.clientHeight,
      navHeight: nav.offsetHeight,
      bottomHeight: bottom.offsetHeight,
      mobile,
    });
    if (ok && mobile) {
      // The stage is position: sticky, so it is the offsetParent of the
      // absolutely placed scenes and label and their offsets are stage pixels.
      // The band starts below the copy plus the scenes' translateY drift.
      const copyBottom = Math.max(...scenes.map(el => el.offsetTop + el.offsetHeight));
      const fit = fitMobileStack({
        top: copyBottom + STACK_GAP + SCENE_DRIFT, bottom: label.offsetTop - STACK_GAP,
        max: Math.min(MAX_STACK_SIZE, win.innerWidth / 550),
      });
      if (fit.size < MIN_STACK_SIZE) ok = false;
      else {
        stackSize = fit.size;
        stage.style.setProperty('--cine-stack-y', `${fit.center.toFixed(1)}px`);
      }
    }
    if (!ok) {
      root.classList.remove('motion-ready');
      if (wasInside) {
        const top = scenes[chapter].getBoundingClientRect().top + win.scrollY - nav.offsetHeight;
        win.scrollTo({ top: Math.max(0, top), behavior: 'instant' });
      }
      staticCh = wasInside ? chapter : staticChapter();
      return;
    }
    measure();
    enabled = true;
    if (wasInside) scrollToChapter(chapter, 'instant');
    current = target = clamp((win.scrollY - trackTop) / travel);
    draw(current);
  }
  let resizeTimer = 0;
  function onResize() {
    // Phone toolbars resize the viewport while scrolling; only rebuild the
    // layout when the size really changed, and never mid-gesture.
    if (Math.abs(win.innerWidth - width) < 1 && Math.abs(win.innerHeight - height) < 120 && enabled) {
      measure(); read(); return;
    }
    win.clearTimeout(resizeTimer);
    resizeTimer = win.setTimeout(reset, 120);
  }
  buttons.forEach((b, i) => b.addEventListener('click', () => {
    if (!enabled) return;
    const top = trackTop + travel * i / 2;
    if (Math.abs(win.scrollY - top) < 2) {
      scenes[i].querySelector('h1, h2')?.focus({ preventScroll: true });
      return;
    }
    focusAfterSettle = i;
    scrollToChapter(i, 'smooth');
  }));
  // If the reader takes over the scroll, never move focus behind their back.
  for (const type of ['wheel', 'touchstart', 'keydown', 'pointerdown']) {
    win.addEventListener(type, () => { focusAfterSettle = -1; }, { passive: true, capture: true });
  }
  // Keyboard and screen-reader users can reach every chapter's text and links:
  // moving focus into a chapter brings that chapter on screen.
  scenes.forEach((el, i) => el.addEventListener('focusin', () => {
    if (enabled && i !== active) scrollToChapter(i, 'instant');
  }));
  win.addEventListener('scroll', read, { passive: true });
  win.addEventListener('resize', onResize);
  media.addEventListener?.('change', reset);
  doc.fonts?.ready?.then(() => { if (enabled) { measure(); read(); } });
  reset();
}
