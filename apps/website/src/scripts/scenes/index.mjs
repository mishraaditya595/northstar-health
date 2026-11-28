import { offlineFrame } from './offline.mjs';
import { trainingFrame, tileFrame } from './training.mjs';

// Frame function per [data-scene-track] name.
export const frames = {
  offline: offlineFrame,
  training: trainingFrame,
  tile: tileFrame,
};
