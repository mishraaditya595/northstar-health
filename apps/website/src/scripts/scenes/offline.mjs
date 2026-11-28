import { seg } from '../scroll-scenes.mjs';

// Signal drops, three sets save with no network, signal returns, the
// finished workout backs up. A pure function of scroll progress.
export function offlineFrame(p) {
  const drop = seg(p, 0, 0.15);
  const back = seg(p, 0.6, 0.72);
  const bars = p < 0.6 ? Math.round(4 * (1 - drop)) : Math.round(4 * back);
  const online = p >= 0.15 && p < 0.72 ? 'no' : 'yes';
  const saved = Math.ceil(seg(p, 0.15, 0.6) * 3);
  const point = p >= 0.95 ? '2' : p >= 0.6 ? '1' : '0';
  return {
    vars: { bars, sync: seg(p, 0.72, 1) },
    attrs: { saved: String(saved), online, point },
  };
}
