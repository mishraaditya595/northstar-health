import { seg } from '../scroll-scenes.mjs';
import { countUpText } from '../home-reveal.mjs';

const ease = t => 1 - Math.pow(1 - t, 3);

// The sample energy score sweeps up from this value, so no step of the scene
// shows a reading of zero (missing is never shown as zero on this site).
export const ENERGY_FROM = 41;

// Sleep wave draws, the energy gauge sweeps up to a sample value, the 7-day
// trend draws, and today's steps climb to their sample total. Resting heart
// rate stays at its sample value and the weight tile stays "No reading": they
// are in the markup and never touched.
export function recoveryFrame(p) {
  const energy = ease(seg(p, 0.15, 0.5));
  const count = ease(seg(p, 0.45, 0.85));
  return {
    vars: { wave: seg(p, 0, 0.3), energy, trend: seg(p, 0.25, 0.6) },
    text: {
      '[data-energy-value]': String(Math.round(ENERGY_FROM + (74 - ENERGY_FROM) * energy)),
      '[data-steps]': countUpText('6,240', count, 4180),
    },
  };
}
