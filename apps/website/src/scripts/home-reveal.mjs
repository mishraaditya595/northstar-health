// Scroll reveals and count-ups for the home page feature demos. The final
// state is the plain HTML: without JS, or with reduced motion, nothing hides.

// Text for a number partway through counting up. Keeps thousands separators
// and decimals; text that is not a plain number is returned unchanged. The
// count starts at `from` (0 unless given).
export function countUpText(text, t, from = 0) {
  if (!/^\d[\d,]*(\.\d+)?$/.test(text)) return text;
  const decimals = (text.split('.')[1] || '').length;
  const value = from + (Number(text.replace(/,/g, '')) - from) * Math.max(0, Math.min(1, t));
  const out = value.toFixed(decimals);
  if (!text.includes(',')) return out;
  const [int, frac] = out.split('.');
  return Number(int).toLocaleString('en-US') + (frac ? `.${frac}` : '');
}

// Words of a heading, with punctuation kept on the word it follows.
export function splitWords(text) {
  return text.split(/\s+/).filter(Boolean);
}

// How far (px) a button leans toward the pointer. The pull is zero at the
// button's centre and at `radius`, strongest halfway, so it never jumps.
export function magnetOffset(dx, dy, radius, max) {
  const d = Math.hypot(dx, dy);
  if (d === 0 || d >= radius) return { x: 0, y: 0 };
  const pull = 4 * (d / radius) * (1 - d / radius) * max;
  return { x: (dx / d) * pull, y: (dy / d) * pull };
}

// Headings marked data-words reveal word by word the first time they enter
// view. The words stay real text; without JS or with reduced motion the
// heading is untouched.
export function mountWords(doc, win) {
  const heads = [...doc.querySelectorAll('[data-words]')];
  if (!heads.length || !('IntersectionObserver' in win)) return;
  const reduce = win.matchMedia?.('(prefers-reduced-motion: reduce)');
  if (reduce?.matches) return;
  for (const h of heads) {
    const words = splitWords(h.textContent);
    h.textContent = '';
    words.forEach((w, i) => {
      const span = doc.createElement('span');
      span.className = 'w';
      span.style.setProperty('--w', String(i));
      span.textContent = w;
      h.append(span);
      if (i < words.length - 1) h.append(' ');
    });
  }
  doc.documentElement.classList.add('words-ready');
  const io = new win.IntersectionObserver(entries => {
    for (const e of entries) {
      if (!e.isIntersecting) continue;
      e.target.classList.add('words-in');
      io.unobserve(e.target);
    }
  }, { rootMargin: '0px 0px -10% 0px', threshold: 0.2 });
  heads.forEach(h => io.observe(h));
  reduce?.addEventListener?.('change', () => {
    if (reduce.matches) { io.disconnect(); heads.forEach(h => h.classList.add('words-in')); }
  });
}

// Buttons lean toward a nearby mouse or trackpad pointer. Fine pointers only.
export function mountMagnets(doc, win, selector = '.finale .button') {
  const fine = win.matchMedia?.('(hover: hover) and (pointer: fine)');
  const motion = win.matchMedia?.('(prefers-reduced-motion: no-preference)');
  if (!fine?.matches) return;
  const buttons = [...doc.querySelectorAll(selector)];
  if (!buttons.length) return;
  let pointer = null, raf = 0;
  const apply = () => {
    raf = 0;
    // Reduced motion may be turned on after load: buttons then stay put.
    if (!motion?.matches) pointer = null;
    const rects = buttons.map(b => b.getBoundingClientRect());
    buttons.forEach((b, i) => {
      const r = rects[i];
      const o = pointer
        ? magnetOffset(pointer.x - (r.left + r.width / 2), pointer.y - (r.top + r.height / 2), Math.max(r.width, 120), 8)
        : { x: 0, y: 0 };
      b.style.translate = pointer ? `${o.x.toFixed(1)}px ${o.y.toFixed(1)}px` : '';
    });
  };
  const zone = buttons[0].closest('.finale') ?? doc.body;
  zone.addEventListener('pointermove', e => {
    pointer = { x: e.clientX, y: e.clientY };
    if (!raf) raf = win.requestAnimationFrame(apply);
  }, { passive: true });
  zone.addEventListener('pointerleave', () => {
    pointer = null;
    if (!raf) raf = win.requestAnimationFrame(apply);
  });
  motion?.addEventListener?.('change', () => { if (!raf) raf = win.requestAnimationFrame(apply); });
}

export function mountReveals(doc, win) {
  const items = [...doc.querySelectorAll('[data-reveal]')];
  if (!items.length || !('IntersectionObserver' in win)) return;
  const reduce = win.matchMedia?.('(prefers-reduced-motion: reduce)');
  if (reduce?.matches) return;
  // Content already on screen when the page loads stays as it is; only
  // sections below the fold wait to play.
  const startY = win.innerHeight;
  items.forEach(el => { if (el.getBoundingClientRect().top < startY) el.classList.add('is-in'); });
  doc.documentElement.classList.add('reveal-ready');
  const counters = el => [...el.querySelectorAll('[data-count]')];
  function count(el) {
    const final = el.dataset.count;
    const start = win.performance.now();
    const step = now => {
      const t = Math.min(1, (now - start) / 1100);
      el.textContent = countUpText(final, 1 - Math.pow(1 - t, 3));
      if (t < 1) win.requestAnimationFrame(step);
    };
    win.requestAnimationFrame(step);
  }
  const io = new win.IntersectionObserver(entries => {
    for (const e of entries) {
      if (!e.isIntersecting) continue;
      e.target.classList.add('is-in');
      counters(e.target).forEach(count);
      io.unobserve(e.target);
    }
  }, { rootMargin: '0px 0px -12% 0px', threshold: .2 });
  items.forEach(el => io.observe(el));
  // If the reader turns on reduced motion, show everything at once.
  reduce?.addEventListener?.('change', () => {
    if (!reduce.matches) return;
    io.disconnect();
    items.forEach(el => {
      el.classList.add('is-in');
      counters(el).forEach(c => { c.textContent = c.dataset.count; });
    });
  });

  // Cursor-following glow on cards, for mouse and trackpad only.
  if (!win.matchMedia?.('(hover: hover) and (pointer: fine)').matches) return;
  doc.querySelectorAll('[data-glow]').forEach(card => {
    card.addEventListener('pointermove', e => {
      const r = card.getBoundingClientRect();
      card.style.setProperty('--mx', `${e.clientX - r.left}px`);
      card.style.setProperty('--my', `${e.clientY - r.top}px`);
    }, { passive: true });
  });
}
