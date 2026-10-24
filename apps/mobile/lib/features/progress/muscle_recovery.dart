import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Muscle groups drawn on the body map. Some appear on both figures.
enum Muscle {
  chest,
  shoulders,
  biceps,
  forearms,
  abs,
  obliques,
  quads,
  calves,
  traps,
  lats,
  lowerBack,
  triceps,
  glutes,
  hamstrings,
}

/// How recently and how hard each muscle was trained, 0 (recovered / not
/// trained) to 1 (just trained hard). Missing means no data, drawn neutral.
class MuscleRecovery {
  const MuscleRecovery(this.load, {required this.isSample});

  final Map<Muscle, double> load;

  /// True while the values are placeholders, not derived from workouts.
  final bool isSample;

  double loadOf(Muscle muscle) => (load[muscle] ?? 0).clamp(0.0, 1.0);

  /// Placeholder values for the layout. No workout is read.
  static const sample = MuscleRecovery({
    Muscle.chest: 0.9,
    Muscle.shoulders: 0.6,
    Muscle.triceps: 0.7,
    Muscle.abs: 0.3,
    Muscle.quads: 0.2,
    Muscle.traps: 0.5,
    Muscle.lats: 0.4,
  }, isSample: true);
}

/// SWAP POINT: replace this provider's body with the real calculation (which
/// workout targeted which muscle, and recovery time). The card only reads
/// [MuscleRecovery], so nothing else changes.
final muscleRecoveryProvider = Provider<MuscleRecovery>(
  (ref) => MuscleRecovery.sample,
);
