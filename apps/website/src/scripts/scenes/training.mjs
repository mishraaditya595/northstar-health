import { seg } from '../scroll-scenes.mjs';

// 0 to 1 across 01:30 down to 00:00.
export function restClock(t) {
  const secs = Math.round(90 * (1 - Math.max(0, Math.min(1, t))));
  return `0${Math.floor(secs / 60)}:${String(secs % 60).padStart(2, '0')}`;
}

const logText = t => ({
  '[data-kg]': String(Math.round(65 + 5 * t)),
  '[data-reps]': String(Math.round(8 - 2 * t)),
});

// Desktop: one pinned panel steps through library, programs, set logging,
// rest timer and progress, each in a fifth of the scroll. Phones and short
// windows show the tiles instead (see tileFrame).
export function trainingFrame(p, ctx = { mobile: false }) {
  if (ctx.mobile || ctx.short) return { attrs: { mode: 'tiles' } };
  const ring = seg(p, 0.6, 0.8);
  return {
    vars: { lib: seg(p, 0, 0.2), prog: seg(p, 0.2, 0.4), log: seg(p, 0.4, 0.6), ring, bars: seg(p, 0.8, 1) },
    attrs: { step: String(Math.min(4, Math.floor(p * 5))), mode: 'pinned' },
    text: { ...logText(seg(p, 0.4, 0.6)), '.timer-text b': restClock(ring) },
  };
}

// Phones: every tile's mini demo scrubs as the tile crosses the screen.
// Elsewhere tiles sit finished and leave the text alone.
export function tileFrame(p, ctx = { mobile: true }) {
  if (!ctx.mobile) return { vars: { k: 1 } };
  return { vars: { k: p }, text: { ...logText(p), '.timer-text b': restClock(p) } };
}
