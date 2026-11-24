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

  /// Version of the read-type list last requested for this account (see
  /// `currentHealthAccessScope`); 0 for Phase 3 connections. Not a health
  /// value.
  int accessScope;

  HealthConnectionEntity({
    this.id = 0,
    required this.ownerAccountId,
    required this.connectedAtMs,
    this.accessScope = 0,
  });
}
