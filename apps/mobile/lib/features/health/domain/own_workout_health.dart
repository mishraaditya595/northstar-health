/// Heart rate and active energy Apple Health holds for one BeyondRep watch
/// workout. Read fresh, held in memory only, never stored or uploaded.
class OwnWorkoutHealth {
  const OwnWorkoutHealth({this.averageBpm, this.maxBpm, this.activeKcal});

  final int? averageBpm;
  final int? maxBpm;
  final double? activeKcal;

  bool get isEmpty =>
      averageBpm == null && maxBpm == null && activeKcal == null;
}
