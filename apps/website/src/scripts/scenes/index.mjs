import { offlineFrame } from './offline.mjs';
import { finaleFrame } from './finale.mjs';
import { privacyFrame } from './privacy.mjs';
import { recoveryFrame } from './recovery.mjs';
import { trainingFrame, tileFrame } from './training.mjs';

// Frame function per [data-scene-track] name.
export const frames = {
  offline: offlineFrame,
  training: trainingFrame,
  tile: tileFrame,
  recovery: recoveryFrame,
  privacy: privacyFrame,
  finale: finaleFrame,
};
