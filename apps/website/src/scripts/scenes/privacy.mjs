import { seg } from '../scroll-scenes.mjs';

const ease = t => t * t * (3 - 2 * t);

// The data starts gathered in a phone outline, then splits: two kinds go to
// the account card, the rest settle in the phone card and it locks.
export function privacyFrame(p) {
  return {
    vars: { split: ease(seg(p, 0.1, 0.7)) },
    attrs: { locked: p >= 0.75 ? 'yes' : 'no' },
  };
}

// Offsets (px) that move each item from its resting place to the centre of
// the area, stacked `gap` px apart in reading order. Pure, so it is tested
// with plain numbers; the DOM measuring is in mountPrivacyOffsets.
export function startOffsets(rects, centre, gap = 34) {
  const cx = centre.x + centre.w / 2, cy = centre.y + centre.h / 2;
  return rects.map((r, i) => ({
    fx: cx - (r.x + r.w / 2),
    fy: cy + (i - (rects.length - 1) / 2) * gap - (r.y + r.h / 2),
  }));
}

// Measures with offsetLeft/offsetTop, which ignore the transforms the scene
// applies, so the numbers stay right while the items are moving.
export function mountPrivacyOffsets(doc, win) {
  const area = doc.querySelector('[data-scene-track="privacy"] .cards');
  if (!area) return;
  const items = [...area.querySelectorAll('.vault li')];
  const place = el => {
    let x = 0, y = 0;
    for (let e = el; e && e !== area; e = e.offsetParent) { x += e.offsetLeft; y += e.offsetTop; }
    return { x, y, w: el.offsetWidth, h: el.offsetHeight };
  };
  let raf = 0;
  function measure() {
    raf = 0;
    // The pile sits below the lower card heading, so neither heading is
    // covered when the scene starts (on phones the cards stack).
    const heads = [...area.querySelectorAll('.vault h3')].map(place);
    const below = Math.max(0, ...heads.map(h => h.y + h.h)) + 8;
    const gap = 44;
    const span = items.length * gap;
    const box = { x: 0, y: below, w: area.offsetWidth, h: Math.max(span, area.offsetHeight - below) };
    const offs = startOffsets(items.map(place), box, gap);
    items.forEach((el, i) => {
      el.style.setProperty('--fx', `${Math.round(offs[i].fx)}px`);
      el.style.setProperty('--fy', `${Math.round(offs[i].fy)}px`);
    });
    area.style.setProperty('--pile-y', `${Math.round(box.y + box.h / 2)}px`);
    area.style.setProperty('--pile-h', `${span + 36}px`);
  }
  const schedule = () => { if (!raf) raf = win.requestAnimationFrame(measure); };
  win.addEventListener('resize', schedule);
  doc.fonts?.ready?.then(schedule);
  schedule();
}
