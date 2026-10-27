import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/storage/account_store.dart';

// Readable after the first unlock so a token refresh during a locked-screen
// workout still persists; `this_device` keeps items out of device backups.
const _secureStorage = FlutterSecureStorage(
  iOptions: IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  ),
);

/// Persists Supabase session credentials in OS-protected storage, not
/// SharedPreferences, ObjectBox, files, analytics, or application logs.
class NorthstarSecureSessionStorage extends LocalStorage {
  NorthstarSecureSessionStorage({required String projectHost})
    : _key = 'northstar.supabase.session.v1.$projectHost';

  final String _key;

  @override
  Future<void> initialize() async {}

  @override
  Future<String?> accessToken() => _secureStorage.read(key: _key);

  @override
  Future<bool> hasAccessToken() => _secureStorage.containsKey(key: _key);

  @override
  Future<void> persistSession(String session) =>
      _secureStorage.write(key: _key, value: session);

  @override
  Future<void> removePersistedSession() => _secureStorage.delete(key: _key);
}

/// An authenticated device can reopen only its last securely bound account.
/// It does not use shared preferences, user-input identifiers, or a JWT decoded
/// without a prior successful Supabase sign-in to authorize local workout data.
abstract class BoundAccountStore {
  Future<String?> read();
  Future<void> write(String userId);
  Future<void> clear();
}

/// A pending deletion is not a grant to open locally protected workouts.
/// Persist the original owner separately from the active account binding.
abstract class DeletionRecoveryStore {
  Future<String?> read();
  Future<void> write(String originalOwner);
  Future<void> clear();
}

class SecureDeletionRecoveryStore implements DeletionRecoveryStore {
  SecureDeletionRecoveryStore({required String projectHost})
    : _key = 'northstar.pending_deletion.v1.$projectHost';

  final String _key;

  @override
  Future<String?> read() => _secureStorage.read(key: _key);

  @override
  Future<void> write(String originalOwner) =>
      _secureStorage.write(key: _key, value: validAccountId(originalOwner));

  @override
  Future<void> clear() => _secureStorage.delete(key: _key);
}

/// Persisted ONLY after receipt confirms server deletion. This marker is
/// deliberately separate from uncertain-result recovery and is retried on
/// startup until the original owner's local directory is gone.
abstract class ConfirmedDeletionCleanupStore {
  Future<String?> read();
  Future<void> write(String accountId);
  Future<void> clear();
}

class SecureConfirmedDeletionCleanupStore
    implements ConfirmedDeletionCleanupStore {
  SecureConfirmedDeletionCleanupStore({required String projectHost})
    : _key = 'northstar.confirmed_deletion_cleanup.v1.$projectHost';

  final String _key;

  @override
  Future<String?> read() => _secureStorage.read(key: _key);

  @override
  Future<void> write(String accountId) =>
      _secureStorage.write(key: _key, value: validAccountId(accountId));

  @override
  Future<void> clear() => _secureStorage.delete(key: _key);
}

/// The production implementation must wait until the owner Store is closed
/// after the account-bound widget subtree has been unmounted.
abstract class LocalAccountDataCleaner {
  Future<void> erase(String owner, {bool waitForUnmount = false});
}

/// Typed, confirmed 4xx from the delete-account handler: no admin deletion
/// was performed. Transport failures and 5xx are ALWAYS ambiguous.
class AccountDeletionRejected implements Exception {
  const AccountDeletionRejected(this.status);
  final int status;
}

class SecureBoundAccountStore implements BoundAccountStore {
  SecureBoundAccountStore({required String projectHost})
    : _key = 'northstar.trusted_account.v1.$projectHost';

  final String _key;

  @override
  Future<String?> read() => _secureStorage.read(key: _key);

  @override
  Future<void> write(String userId) =>
      _secureStorage.write(key: _key, value: userId);

  @override
  Future<void> clear() => _secureStorage.delete(key: _key);
}

/// Kept behind an interface to test without real accounts or live emails.
/// The RPC is NOT called here; P2-02 only gates the locally stored logger.
abstract class AccountAuthApi {
  String? get signedInUserId;
  bool get isAnonymous;

  /// A presently unexpired, non-anonymous session; null pauses cloud upload.
  String? get cloudSessionUserId;

  /// Token deadline (UTC Unix seconds). Null for APIs without a deadline.
  /// Used only to refresh UI state, never to grant cloud access.
  int? get cloudSessionExpiresAtSeconds => null;

  Stream<String?> get cloudIdentityChanges;

  Future<void> sendEmailCode(String email);

  /// Recovery never registers a new Auth user.
  Future<void> sendRecoveryCode(String email);
  Future<String> verifyEmailCode(String email, String code);
  Future<void> signOutLocally();

  /// Email is read from the signed-in Auth user, never typed by a caller.
  String? get signedInEmail;

  /// Re-verification must start a NEW session, not merely refresh a JWT.
  Future<void> sendDeletionCode(String email);
  Future<String> verifyDeletionCode(String email, String code);

  /// Calls a server-only Edge Function; never bundles an admin key in mobile.
  Future<void> deleteAccountOnServer(String accountId);
}

class SupabaseAccountAuthApi implements AccountAuthApi {
  SupabaseAccountAuthApi(this._client);

  final SupabaseClient _client;

  @override
  String? get signedInUserId => _client.auth.currentSession?.user.id;

  @override
  bool get isAnonymous =>
      _client.auth.currentSession?.user.isAnonymous ?? false;

  @override
  String? get cloudSessionUserId {
    final session = _client.auth.currentSession;
    final expiresAt = session?.expiresAt;
    if (session == null ||
        session.user.isAnonymous ||
        expiresAt == null ||
        expiresAt <= DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000) {
      return null;
    }
    return session.user.id;
  }

  @override
  int? get cloudSessionExpiresAtSeconds =>
      _client.auth.currentSession?.expiresAt;

  @override
  Stream<String?> get cloudIdentityChanges =>
      _client.auth.onAuthStateChange.map((_) => cloudSessionUserId);

  @override
  Future<void> sendEmailCode(String email) =>
      _client.auth.signInWithOtp(email: email, shouldCreateUser: true);

  @override
  Future<void> sendRecoveryCode(String email) =>
      _client.auth.signInWithOtp(email: email, shouldCreateUser: false);

  @override
  Future<String> verifyEmailCode(String email, String code) async {
    final response = await _client.auth.verifyOTP(
      email: email,
      token: code,
      type: OtpType.email,
    );
    if (response.session == null ||
        response.user == null ||
        response.user!.isAnonymous) {
      throw const AuthException('Unable to verify this account.');
    }
    return response.user!.id;
  }

  @override
  Future<void> signOutLocally() =>
      _client.auth.signOut(scope: SignOutScope.local);

  @override
  String? get signedInEmail => _client.auth.currentSession?.user.email;

  @override
  Future<void> sendDeletionCode(String email) =>
      _client.auth.signInWithOtp(email: email, shouldCreateUser: false);

  @override
  Future<String> verifyDeletionCode(String email, String code) async {
    final answer = await _client.auth.verifyOTP(
      email: email,
      token: code,
      type: OtpType.email,
    );
    final user = answer.user;
    if (answer.session == null || user == null || user.isAnonymous) {
      throw const AuthException('Fresh verification required');
    }
    return user.id;
  }

  @override
  Future<void> deleteAccountOnServer(String accountId) async {
    final session = _client.auth.currentSession;
    if (session == null ||
        session.user.id != accountId ||
        session.user.isAnonymous ||
        session.expiresAt == null ||
        session.expiresAt! <=
            DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000) {
      throw const AuthException('Verified account required');
    }
    late final FunctionResponse response;
    try {
      response = await _client.functions.invoke(
        'delete-account',
        body: {'account_id': accountId, 'confirm': 'DELETE MY ACCOUNT'},
      );
    } on FunctionsHttpException catch (error) {
      if (error.status == 400 || error.status == 401 || error.status == 403) {
        throw AccountDeletionRejected(error.status);
      }
      rethrow;
    }
    if (response.status == 400 ||
        response.status == 401 ||
        response.status == 403) {
      throw AccountDeletionRejected(response.status);
    }
    final data = response.data;
    if (response.status != 200 ||
        data is! Map ||
        data['schema_version'] != 1 ||
        data['deleted'] != true) {
      throw const AuthException('Deletion receipt missing');
    }
  }
}

/// No listener ever receives credentials. A prior online verification writes
/// the bound user ID into OS secure storage. When a token refresh cannot run
/// offline, only that same account may open its partitioned local database.
class AccountAuthController extends ChangeNotifier {
  AccountAuthController(
    this._api,
    this._binding,
    this._recoveryStore, {
    required ConfirmedDeletionCleanupStore cleanupStore,
    required LocalAccountDataCleaner localCleaner,
  }) : _cleanupStore = cleanupStore,
       _localCleaner = localCleaner {
    _authSubscription = _api.cloudIdentityChanges.listen(
      _onIdentityChange,
      onError: (Object _) {
        _refreshFailed = true;
        _onIdentityChange(null);
      },
    );
  }

  final AccountAuthApi _api;
  final BoundAccountStore _binding;
  final DeletionRecoveryStore _recoveryStore;
  final ConfirmedDeletionCleanupStore _cleanupStore;
  final LocalAccountDataCleaner _localCleaner;
  late final StreamSubscription<String?> _authSubscription;
  Timer? _sessionExpiryTimer;
  bool _refreshFailed = false;

  void _scheduleSessionExpiry() {
    _sessionExpiryTimer?.cancel();
    _sessionExpiryTimer = null;
    final expiresAt = _api.cloudSessionExpiresAtSeconds;
    if (_userId == null ||
        expiresAt == null ||
        _accountIdOrNull(_api.cloudSessionUserId) != _userId) {
      return;
    }
    final deadline = DateTime.fromMillisecondsSinceEpoch(
      expiresAt * 1000,
      isUtc: true,
    );
    final remaining = deadline.difference(DateTime.now().toUtc());
    if (remaining <= Duration.zero) return;
    // Refresh the disabled state at the actual JWT deadline even when the
    // SDK does not send an auth event. Transport still rechecks every RPC.
    _sessionExpiryTimer = Timer(remaining, () {
      _sessionExpiryTimer = null;
      notifyListeners();
    });
  }

  void _onIdentityChange(String? accountId) {
    // Look at the restored session's owner even if its JWT has expired.
    // A different expired account must never keep the previous user's
    // ObjectBox partition mounted.
    final sessionOwner = _accountIdOrNull(_api.signedInUserId);
    if (_userId != null && sessionOwner != null && sessionOwner != _userId) {
      // A different user's live JWT must immediately unmount this account's
      // ObjectBox Store. Keep its protected binding for future recovery.
      _userId = null;
    }
    if (accountId != null) _refreshFailed = false;
    _scheduleSessionExpiry();
    notifyListeners();
  }

  /// This is a UI/worker permission hint, not server authorization.
  /// P2-04 must still let Supabase enforce token validity and RLS.
  bool get cloudBackupReady =>
      _userId != null &&
      !_refreshFailed &&
      !_api.isAnonymous &&
      _accountIdOrNull(_api.cloudSessionUserId) == _userId;

  bool get backupPaused => _userId != null && !cloudBackupReady;

  String? _userId;
  bool _busy = false;
  bool _codeSent = false;
  String? _error;
  String? _pendingEmail;

  String? _recoveryOwner;

  /// This is a lock, never an authentication grant.
  bool get deletionRecoveryPending => _recoveryOwner != null;
  String? _cleanupOwner;
  bool get confirmedLocalCleanupPending => _cleanupOwner != null;

  String? _deletionEmail;
  String? _deletionOwner;
  bool _deletionCodeSent = false;
  String? _notice;

  bool get deletionCodeSent => _deletionCodeSent;
  String? get notice => _notice;

  String? get userId => _userId;
  bool get busy => _busy;
  bool get codeSent => _codeSent;
  String? get error => _error;
  bool get isAuthenticated => _userId != null;

  /// Called only after Supabase has restored its securely persisted session.
  /// If an online SDK session belongs to a different account, no partition
  /// is opened: explicit reauthentication is required. With no session at
  /// all (refresh token rejected), ADR-0005 keeps the bound owner's local
  /// access; cloud transfer must re-authenticate first.
  /// A corrupt binding counts as no binding; account data stays on disk.
  Future<void> restore() async {
    final cleanup = await _cleanupStore.read();
    if (cleanup != null) {
      // A confirmed server delete takes precedence over any stale binding.
      _cleanupOwner = validAccountId(cleanup);
      _userId = null;
      await retryConfirmedLocalCleanup();
      return;
    }
    final pending = await _recoveryStore.read();
    // Invalid protected state must not silently allow ordinary sign-in.
    _recoveryOwner = pending == null ? null : validAccountId(pending);
    final bound = _accountIdOrNull(await _binding.read());
    final active = _api.signedInUserId;
    if (_recoveryOwner == null &&
        bound != null &&
        (active == null ||
            (!_api.isAnonymous && _accountIdOrNull(active) == bound))) {
      _userId = bound;
    }
    _scheduleSessionExpiry();
    notifyListeners();
  }

  /// Run before normal sign-in on launch and after confirmed remote success.
  /// Failed file erasure retains the durable cleanup marker for next launch.
  Future<void> retryConfirmedLocalCleanup({bool waitForUnmount = false}) async {
    final owner = _cleanupOwner;
    if (owner == null) return;
    _busy = true;
    _error = null;
    _userId = null;
    notifyListeners();
    try {
      await _localCleaner.erase(owner, waitForUnmount: waitForUnmount);
      await _binding.clear();
      await _recoveryStore.clear();
      await _cleanupStore.clear();
      _cleanupOwner = null;
      _recoveryOwner = null;
      _notice = 'Account deleted and local workout data erased.';
      try {
        await _api.signOutLocally();
      } catch (_) {
        // Local data and binding are already removed.
      }
    } catch (_) {
      _notice = null;
      _error =
          'Cloud account deleted. Local cleanup is not complete. '
          'Data stays locked; retry removal or restart the app.';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  static String? _accountIdOrNull(String? value) {
    if (value == null) return null;
    try {
      return validAccountId(value);
    } on FormatException {
      return null;
    }
  }

  /// Email proof must come from Supabase's currently bound, live account.
  /// Sending the code cannot silently create a new Auth identity.
  Future<void> requestDeletionCode() async {
    if (_busy || !cloudBackupReady || _userId == null) return;
    final email = _api.signedInEmail;
    if (email == null || email.isEmpty) {
      _error = 'A verified email address is required to delete this account.';
      notifyListeners();
      return;
    }
    _busy = true;
    _error = null;
    _notice = null;
    notifyListeners();
    try {
      await _api.sendDeletionCode(email);
      if (!cloudBackupReady || _api.signedInEmail != email) {
        throw StateError('Account identity changed');
      }
      _deletionOwner = _userId;
      _deletionEmail = email;
      _deletionCodeSent = true;
    } on AuthApiException catch (error) {
      _error = error.statusCode == '429'
          ? 'Too many email codes requested. Wait before trying again.'
          : 'Could not send deletion code. Check your connection and retry.';
    } catch (_) {
      _error = 'Could not send deletion code. Check your connection and retry.';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  void cancelDeletion() {
    if (_busy) return;
    _deletionEmail = null;
    _deletionOwner = null;
    _deletionCodeSent = false;
    _error = null;
    notifyListeners();
  }

  /// Re-verify an OTP to create a fresh Auth session. Stop the owner-bound
  /// foreground uploader by clearing the binding and unmounting the owner
  /// BEFORE the privileged remote deletion request.
  ///
  /// On an ambiguous HTTP result we remain locked. The user may sign in
  /// again to their *same* existing account only if deletion did not commit.
  /// An old local partition is never reassigned to a newly created account.
  Future<void> confirmAccountDeletion(String code) async {
    if (_busy || !_deletionCodeSent) return;
    if (_deletionEmail == null ||
        _deletionOwner == null ||
        _userId != _deletionOwner ||
        !cloudBackupReady) {
      _deletionCodeSent = false;
      _deletionEmail = null;
      _deletionOwner = null;
      _error =
          'Your verified session expired or changed. '
          'Request a new deletion code after signing in again.';
      notifyListeners();
      return;
    }
    if (!RegExp(r'^\d{6}$').hasMatch(code.trim())) {
      _error = 'Enter the six-digit deletion verification code.';
      notifyListeners();
      return;
    }
    _busy = true;
    _error = null;
    notifyListeners();
    final owner = _deletionOwner!;
    try {
      final verified = _accountIdOrNull(
        await _api.verifyDeletionCode(_deletionEmail!, code.trim()),
      );
      if (verified != owner ||
          _api.cloudSessionUserId != owner ||
          _userId != owner ||
          _api.isAnonymous) {
        throw StateError('Deletion verification account mismatch');
      }
    } catch (_) {
      _error =
          'Verification failed or the account changed. '
          'Check the code and sign in again if necessary.';
      _busy = false;
      notifyListeners();
      return;
    }

    try {
      await _binding.clear();
    } catch (_) {
      _error =
          'Could not lock this device securely. '
          'Account deletion has not been requested.';
      _busy = false;
      notifyListeners();
      return;
    }

    // Stop foreground workers immediately after the durable local lock.
    // No destructive request is sent until recovery is also durable.
    _userId = null;
    _sessionExpiryTimer?.cancel();
    _sessionExpiryTimer = null;
    _deletionCodeSent = false;
    _deletionOwner = null;
    _deletionEmail = null;
    notifyListeners();
    try {
      await _recoveryStore.write(owner);
      _recoveryOwner = owner;
    } catch (_) {
      // No remote deletion occurred. The original partition stays locked.
      _error =
          'Could not save safe deletion recovery on this device. '
          'Account deletion has not been requested. Sign in again.';
      _busy = false;
      notifyListeners();
      return;
    }
    var serverConfirmed = false;
    try {
      await _api.deleteAccountOnServer(owner);
      serverConfirmed = true;
      // This write MUST occur only after an exact successful server receipt.
      // A lost response keeps the uncertain marker; it never erases files.
      await _cleanupStore.write(owner);
      _cleanupOwner = owner;
      await retryConfirmedLocalCleanup(waitForUnmount: true);
    } on AccountDeletionRejected catch (_) {
      // 400/401/403 are explicit pre-deletion refusals, unlike 5xx or timeouts.
      // Rebind only while the SAME verified Auth identity is still current.
      if (_api.cloudSessionUserId == owner &&
          _api.signedInUserId == owner &&
          !_api.isAnonymous) {
        try {
          await _binding.write(owner);
          await _recoveryStore.clear();
          _recoveryOwner = null;
          _userId = owner;
          _scheduleSessionExpiry();
          _error =
              'Deletion was refused. Your account and local workouts '
              'are unchanged. Request a new verification code to retry.';
        } catch (_) {
          _error =
              'Deletion was refused, but local access could not be '
              'restored securely. Recover the original account to unlock.';
        }
      } else {
        _error =
            'Deletion was refused and your session has changed. '
            'Recover the original account to unlock local workouts.';
      }
    } catch (_) {
      // A response can disappear AFTER the server commit. Only a confirmed
      // receipt is permitted to authorize local file erasure.
      _error = serverConfirmed
          ? 'Cloud deletion confirmed, but local cleanup could not be '
                'secured. Data stays locked; contact support.'
          : 'Account deletion could not be confirmed. This device is '
                'locked. Recover ONLY the original account if it still exists; '
                'otherwise contact support. Recovery never creates an account.';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> requestCode(String email) async {
    if (_busy || _cleanupOwner != null) return;
    final normalized = email.trim().toLowerCase();
    if (!normalized.contains('@') || normalized.length > 254) {
      _error = 'Enter a valid email address.';
      notifyListeners();
      return;
    }
    _busy = true;
    _error = null;
    _notice = null;
    notifyListeners();
    try {
      if (_recoveryOwner != null) {
        await _api.sendRecoveryCode(normalized);
      } else {
        await _api.sendEmailCode(normalized);
      }
      _pendingEmail = normalized;
      _codeSent = true;
    } on AuthApiException catch (error) {
      _error = error.statusCode == '429'
          ? 'Too many email codes requested. Wait before trying again.'
          : 'Could not send a code. Check your connection and retry.';
    } catch (_) {
      _error = 'Could not send a code. Check your connection and retry.';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  void changeEmail() {
    if (_busy) return;
    _pendingEmail = null;
    _codeSent = false;
    _error = null;
    notifyListeners();
  }

  Future<void> verifyCode(String value) async {
    if (_busy || _cleanupOwner != null || _pendingEmail == null) return;
    final code = value.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      _error = 'Enter the six-digit email code.';
      notifyListeners();
      return;
    }
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      final identity = validAccountId(
        await _api.verifyEmailCode(_pendingEmail!, code),
      );
      // A different existing account can also verify an OTP; only the
      // original verified Auth UUID is permitted to restore this binding.
      if (_recoveryOwner != null && identity != _recoveryOwner) {
        try {
          await _api.signOutLocally();
        } catch (_) {
          // The secure recovery marker remains authoritative.
        }
        throw StateError('Recovery owner mismatch');
      }
      try {
        await _binding.write(identity);
        if (_recoveryOwner != null) {
          // A failed marker clear stays locked across app restarts.
          await _recoveryStore.clear();
          _recoveryOwner = null;
        }
      } catch (_) {
        _error =
            'This device could not save your sign-in securely. '
            'Send a new code to retry.';
        _codeSent = false;
        return;
      }
      _userId = identity;
      _scheduleSessionExpiry();
      _codeSent = false;
      _pendingEmail = null;
    } catch (_) {
      _error = _recoveryOwner == null
          ? 'Verification failed. Check the code and try again.'
          : 'Could not recover the original account. No new account was '
                'created. Check the email and code, or contact support.';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Explicit abandonment never deletes, opens or reassigns local workouts.
  /// The UI must show a confirmation warning before invoking this.
  Future<void> leaveDeletionRecovery() async {
    if (_busy || _recoveryOwner == null || _userId != null) return;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      // A crash after recovery wrote a binding but before the recovery
      // marker was cleared can leave BOTH keys present. Clear the binding
      // first: abandoning recovery must never unlock it on next launch.
      await _binding.clear();
      await _recoveryStore.clear();
      _recoveryOwner = null;
      _codeSent = false;
      _pendingEmail = null;
      _notice = null;
      try {
        await _api.signOutLocally();
      } catch (_) {
        // No active local binding remains.
      }
    } catch (_) {
      _error = 'Could not clear the recovery lock securely. Retry or contact support.';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Local lock happens before any asynchronous SDK sign-out. Other users
  /// cannot see or mutate the previous account's ObjectBox Store.
  Future<void> signOut() async {
    if (_busy) return;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      // If removing this binding fails, retain the account and report an
      // error. Never present a successful sign-out while the grant persists.
      await _binding.clear();
    } catch (_) {
      _error = 'Could not finish signing out. Retry before sharing the device.';
      _busy = false;
      notifyListeners();
      return;
    }
    _userId = null;
    _sessionExpiryTimer?.cancel();
    _sessionExpiryTimer = null;
    _codeSent = false;
    _pendingEmail = null;
    _deletionEmail = null;
    _deletionOwner = null;
    _deletionCodeSent = false;
    notifyListeners();
    try {
      await _api.signOutLocally();
    } catch (_) {
      // The binding is gone, so the device is already locked. Supabase drops
      // its local session before the network revoke, so an offline revoke
      // failure is not a failed sign-out.
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _sessionExpiryTimer?.cancel();
    _authSubscription.cancel();
    super.dispose();
  }
}
