// Only animate content that was below the fold when enhancement starts.
// Never hide targets before observation: no JS, no observer, or a failed
// callback leaves the same readable, accessible static page.
export function revealBelowFold(doc, win) {
  if (!win.IntersectionObserver || !win.matchMedia ||
      win.matchMedia('(prefers-reduced-motion: reduce)').matches) return;

  const selector = 'main section .section-title, main section .cards > .card, main section .cards > .panel';
  const targets = [...doc.querySelectorAll(selector)]
    .filter((target) => target.getBoundingClientRect().top >= win.innerHeight);

  if (!targets.length) return;
  const observer = new win.IntersectionObserver((entries) => {
    for (const entry of entries) {
      if (!entry.isIntersecting) continue;
      if (!win.matchMedia('(prefers-reduced-motion: reduce)').matches &&
          !entry.target.contains(doc.activeElement)) {
        entry.target.classList.add('home-reveal');
      }
      observer.unobserve(entry.target);
    }
  }, { threshold: 0 });
  targets.forEach((target) => observer.observe(target));
}
