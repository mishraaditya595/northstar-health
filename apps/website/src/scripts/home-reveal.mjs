// Scroll reveals and count-ups for the home page feature demos. The final
// state is the plain HTML: without JS, or with reduced motion, nothing hides.

// Text for a number partway through counting up. Keeps thousands separators
// and decimals; text that is not a plain number is returned unchanged.
export function countUpText(text, t) {
  if (!/^\d[\d,]*(\.\d+)?$/.test(text)) return text;
  const decimals = (text.split('.')[1] || '').length;
  const value = Number(text.replace(/,/g, '')) * Math.max(0, Math.min(1, t));
  const out = value.toFixed(decimals);
  if (!text.includes(',')) return out;
  const [int, frac] = out.split('.');
  return Number(int).toLocaleString('en-US') + (frac ? `.${frac}` : '');
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
