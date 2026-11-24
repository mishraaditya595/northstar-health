import 'package:objectbox/objectbox.dart';

/// Presence of a row means the account opted in to reading platform health
/// data. Lives only in the account-bound ObjectBox store; never synced.
@Entity()
class HealthConnectionEntity {
  @Id()
  int id = 0;
  @Unique()
  String ownerAccountId;
  int connectedAtMs;

  HealthConnectionEntity({
    this.id = 0,
    required this.ownerAccountId,
    required this.connectedAtMs,
  });
}
