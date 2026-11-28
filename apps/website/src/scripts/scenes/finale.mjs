import { seg } from '../scroll-scenes.mjs';

// The call-to-action rings scale out and turn as the card pins.
export function finaleFrame(p) {
  const t = seg(p, 0, 0.9);
  return { vars: { rings: 1 - Math.pow(1 - t, 3) } };
}
