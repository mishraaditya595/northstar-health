import { seg } from '../scroll-scenes.mjs';
import { countUpText } from '../home-reveal.mjs';

const ease = t => 1 - Math.pow(1 - t, 3);

// Sleep wave draws, the energy gauge sweeps to a sample value, the 7-day
// trend draws, then steps and resting heart rate count up. The weight tile
// stays "No reading" in the markup and is never touched.
export function recoveryFrame(p) {
  const energy = ease(seg(p, 0.3, 0.65));
  const count = ease(seg(p, 0.6, 1));
  return {
    vars: { wave: seg(p, 0, 0.35), energy, trend: seg(p, 0.5, 0.85) },
    text: {
      '[data-energy-value]': String(Math.round(74 * energy)),
      '[data-steps]': countUpText('6,240', count),
      '[data-rhr]': countUpText('58', count),
    },
  };
}
