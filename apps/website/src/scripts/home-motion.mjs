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

export function cinematicFrame(progress, width, height) {
  const p = clamp(progress);
  const mobile = width <= 720;
  const size = mobile ? Math.min(.69, width / 550, height / 1130)
    : Math.min(1.17, width / 1150, height / 720);
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

export function mountCinematic(root, win) {
  const stage = root.querySelector('[data-stage]');
  const word = root.querySelector('[data-word]');
  const scenes = [...root.querySelectorAll('[data-scene]')];
  const rigs = [...root.querySelectorAll('[data-rig]')];
  const buttons = [...root.querySelectorAll('[data-chapter]')];
  if (!stage || !word || scenes.length !== 3 || rigs.length !== 3 ||
      buttons.length !== 3 || !win.matchMedia || !win.requestAnimationFrame) return;
  const media = win.matchMedia('(prefers-reduced-motion: reduce), (max-height: 580px)');
  // At large text zoom a pinned viewport can clip content. Fall back when
  // the desktop/mobile copy cannot fit into its allocated vertical space.
  let current = 0, target = 0, raf = 0, enabled = false;
  function draw(p) {
    const frame = cinematicFrame(p, win.innerWidth, win.innerHeight);
    stage.style.setProperty('--p', String(p));
    rigs.forEach((el,i) => {
      const v = frame.rigs[i];
      el.style.transform = `translate(-50%,-50%) translate3d(${v.x}px,${v.y}px,${v.z}px) rotateX(${v.rx}deg) rotateY(${v.ry}deg) rotateZ(${v.ry*.22}deg) scale(${v.scale})`;
      el.style.opacity = String(v.opacity);
      el.style.zIndex = String(v.order);
    });
    scenes.forEach((el,i) => {
      const v = frame.scenes[i];
      const inactive = i !== frame.active || v.opacity < .5;
      if (inactive && el.contains(root.ownerDocument.activeElement)) {
        buttons[frame.active].focus({ preventScroll: true });
      }
      el.style.opacity = String(v.opacity);
      el.style.transform = frame.mobile ? `translateY(${v.drift}px)` : `translateY(calc(-50% + ${v.drift}px))`;
      el.style.visibility = v.opacity > 0 ? 'visible' : 'hidden';
      el.style.pointerEvents = inactive ? 'none' : 'auto';
      el.inert = inactive;
    });
    word.textContent = ['REP.','LIFT.','REST.'][frame.active];
    buttons.forEach((b,i) => {
      if (i === frame.active) b.setAttribute('aria-current','true');
      else b.removeAttribute('aria-current');
    });
  }
  function loop() {
    raf = 0;
    if (!enabled) return;
    current += (target-current)*.16;
    if (Math.abs(target-current)<.001) current = target;
    draw(current);
    if (current !== target) raf = win.requestAnimationFrame(loop);
  }
  function read() {
    if (!enabled) return;
    target = progressForScroll(root.getBoundingClientRect().top, root.offsetHeight, stage.offsetHeight);
    if (!raf) raf = win.requestAnimationFrame(loop);
  }
  function disable() {
    enabled = false;
    if (raf) win.cancelAnimationFrame(raf);
    raf = 0;
    root.classList.remove('motion-ready');
    scenes.forEach(el => {
      el.inert = false;
      el.style.removeProperty('opacity');
      el.style.removeProperty('transform');
      el.style.removeProperty('visibility');
      el.style.removeProperty('pointer-events');
    });
  }
  function reset() {
    if (media.matches) { disable(); return; }
    root.classList.add('motion-ready');
    // Measure without hiding content; if text enlargement or short viewports
    // would cause overlap, keep the complete static introduction instead.
    const available = stage.clientHeight * (win.innerWidth <= 720 ? .43 : .70);
    if (scenes.some(el => el.offsetHeight > available)) { disable(); return; }
    enabled = true;
    current = target = progressForScroll(root.getBoundingClientRect().top,root.offsetHeight,stage.offsetHeight);
    draw(current);
  }
  buttons.forEach((b,i) => b.addEventListener('click',() => {
    if (!enabled) return;
    const y = win.scrollY + root.getBoundingClientRect().top + (root.offsetHeight-stage.offsetHeight)*i/2;
    win.scrollTo({top:y,behavior:'smooth'});
  }));
  win.addEventListener('scroll',read,{passive:true});
  win.addEventListener('resize',reset);
  media.addEventListener?.('change',reset);
  reset();
}
