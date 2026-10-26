/// Shared authentication predicate for cloud workout upload and restore.
/// This is a local preflight only: Supabase JWT verification and RLS are final.
bool matchesCloudWorkoutSession({
  required String? sessionUserId,
  required bool anonymous,
  required int? expiresAtSeconds,
  required String accountId,
  required int nowSeconds,
}) =>
    sessionUserId != null &&
    sessionUserId.toLowerCase() == accountId.toLowerCase() &&
    !anonymous &&
    expiresAtSeconds != null &&
    expiresAtSeconds > nowSeconds;
