// Scroll-scrubbed scenes. Each scene is a tall track with a sticky stage; a
// pure frame function turns the track's scroll progress (0 to 1) into custom
// properties, data attributes and text on the track. Scrolling back reverses
// it, nothing runs on a timer, and without motion, JS or the APIs below the
// plain finished markup stays as it is.
import { MOTION_QUERY, setIfChanged } from './home-motion.mjs';

const clamp = (n, a = 0, b = 1) => Math.max(a, Math.min(b, n));

// 0 when the stage pins (track top at the viewport top), 1 when it releases.
export function sceneProgress(top, trackHeight, viewportHeight) {
  return clamp(-top / Math.max(1, trackHeight - viewportHeight));
}

// For blocks shorter than the screen: 0 when the block's top is at 85% of the
// viewport, 1 once its centre has reached 45%.
export function crossProgress(top, height, viewportHeight) {
  return clamp((viewportHeight * 0.85 - top) / (viewportHeight * 0.4 + height / 2));
}

// Share of the scrollable page already scrolled, for the progress bar.
export function pageProgress(scrollY, scrollHeight, viewportHeight) {
  return clamp(scrollY / Math.max(1, scrollHeight - viewportHeight));
}

// Local 0 to 1 progress of p inside the window [a, b].
export function seg(p, a, b) {
  return clamp((p - a) / (b - a));
}

export function mountScenes(doc, win, frames) {
  const root = doc.documentElement;
  if (!win.matchMedia || !win.IntersectionObserver || !win.requestAnimationFrame) return () => {};
  const media = win.matchMedia(MOTION_QUERY);
  const tracks = [...doc.querySelectorAll('[data-scene-track]')];
  const frameFor = track => {
    const name = track.dataset.sceneTrack;
    return frames[name] ?? frames[name.replace(/-\d+$/, '')];
  };
  const written = new Map();
  // What each track has had written to it, so it can be undone.
  const touched = new Map(tracks.map(t => [t, { vars: new Set(), attrs: new Set(), texts: new Map() }]));
  const visible = new Set();
  // Height the stage covers while pinned (its own height plus its sticky top),
  // measured again after a resize. A stage as tall as the screen gives vh.
  const pins = new Map();
  function pinHeight(track, vh) {
    if (pins.has(track)) return pins.get(track);
    const stage = track.querySelector('[data-scene-stage]');
    let pin = vh;
    if (stage?.offsetHeight) {
      const top = parseFloat(win.getComputedStyle?.(stage).top) || 0;
      pin = Math.min(vh, stage.offsetHeight + top);
    }
    pins.set(track, pin);
    return pin;
  }
  let dirty = new Set();
  let io = null, raf = 0, enabled = false;

  function apply(track, state) {
    const mine = touched.get(track);
    const put = (key, value, write) => setIfChanged(written, track, key, value, write);
    for (const [k, v] of Object.entries(state.vars ?? {})) {
      mine.vars.add(k);
      put('v:' + k, String(v), s => track.style.setProperty('--' + k, s));
    }
    for (const [k, v] of Object.entries(state.attrs ?? {})) {
      mine.attrs.add(k);
      put('a:' + k, String(v), s => { track.dataset[k] = s; });
    }
    // Keys a frame stops returning go back to their resting value.
    const seen = written.get(track) ?? {};
    const forget = key => { delete seen[key]; };
    for (const k of [...mine.vars]) if (!(k in (state.vars ?? {}))) { track.style.removeProperty('--' + k); mine.vars.delete(k); forget('v:' + k); }
    for (const k of [...mine.attrs]) if (!(k in (state.attrs ?? {}))) { delete track.dataset[k]; mine.attrs.delete(k); forget('a:' + k); }
    for (const [sel, rec] of [...mine.texts]) if (!(sel in (state.text ?? {}))) { rec.target.textContent = rec.original; mine.texts.delete(sel); forget('t:' + sel); }
    for (const [sel, text] of Object.entries(state.text ?? {})) {
      let rec = mine.texts.get(sel);
      if (!rec) {
        const target = track.querySelector(sel);
        if (!target) continue;
        rec = { target, original: target.textContent };
        mine.texts.set(sel, rec);
      }
      put('t:' + sel, text, s => { rec.target.textContent = s; });
    }
  }
  function undo() {
    for (const [track, mine] of touched) {
      mine.vars.forEach(k => track.style.removeProperty('--' + k));
      mine.attrs.forEach(k => { delete track.dataset[k]; });
      mine.texts.forEach(rec => { rec.target.textContent = rec.original; });
      mine.vars.clear(); mine.attrs.clear(); mine.texts.clear();
    }
    written.clear();
  }

  function frame() {
    raf = 0;
    if (!enabled) return;
    const vh = win.innerHeight;
    const ctx = { mobile: win.innerWidth < 900, short: vh < 720 };
    const todo = tracks.filter(t => visible.has(t) || dirty.has(t));
    dirty = new Set();
    // Read every rect first, then write, so the frame forces one layout.
    const rects = todo.map(t => t.getBoundingClientRect());
    todo.forEach((track, i) => {
      const fn = frameFor(track);
      if (!fn) return;
      const r = rects[i];
      const p = track.dataset.sceneMode === 'cross'
        ? crossProgress(r.top, r.height, vh)
        : sceneProgress(r.top, r.height, pinHeight(track, vh));
      apply(track, fn(p, ctx));
    });
  }
  function schedule() {
    if (!raf && enabled) raf = win.requestAnimationFrame(frame);
  }
  // Thin page-progress bar; its custom property is written on the bar itself
  // so no other element restyles.
  const bar = doc.querySelector('[data-page-progress]');
  function onScroll() {
    if (bar && enabled) {
      const v = pageProgress(win.scrollY, root.scrollHeight, win.innerHeight).toFixed(4);
      setIfChanged(written, bar, 'page', v, x => bar.style.setProperty('--page', x));
    }
    if (visible.size) schedule();
  }
  function onResize() {
    pins.clear();
    tracks.forEach(t => dirty.add(t));
    schedule();
  }

  function enable() {
    if (enabled) return;
    enabled = true;
    root.classList.add('scenes-ready');
    io = new win.IntersectionObserver(entries => {
      for (const e of entries) {
        if (e.isIntersecting) visible.add(e.target); else visible.delete(e.target);
        dirty.add(e.target);
      }
      schedule();
    }, { rootMargin: '10% 0px' });
    tracks.forEach(t => { dirty.add(t); io.observe(t); });
    onScroll();
    schedule();
  }
  function disable() {
    if (!enabled) return;
    enabled = false;
    if (raf) win.cancelAnimationFrame(raf);
    raf = 0;
    io?.disconnect(); io = null;
    visible.clear(); dirty = new Set(); pins.clear();
    root.classList.remove('scenes-ready');
    undo();
    bar?.style.removeProperty('--page');
  }
  const onMedia = () => { if (media.matches) enable(); else disable(); };

  win.addEventListener('scroll', onScroll, { passive: true });
  win.addEventListener('resize', onResize);
  media.addEventListener?.('change', onMedia);
  if (media.matches) enable();

  return function teardown() {
    disable();
    win.removeEventListener('scroll', onScroll);
    win.removeEventListener('resize', onResize);
    media.removeEventListener?.('change', onMedia);
  };
}
