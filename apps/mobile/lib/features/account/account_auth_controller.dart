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
    final response = await _client.functions.invoke(
      'delete-account',
      body: {'account_id': accountId, 'confirm': 'DELETE MY ACCOUNT'},
    );
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
  AccountAuthController(this._api, this._binding) {
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
    final bound = _accountIdOrNull(await _binding.read());
    final active = _api.signedInUserId;
    if (bound != null &&
        (active == null ||
            (!_api.isAnonymous && _accountIdOrNull(active) == bound))) {
      _userId = bound;
    }
    _scheduleSessionExpiry();
    notifyListeners();
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
    if (_busy ||
        !_deletionCodeSent ||
        _deletionEmail == null ||
        _deletionOwner == null ||
        _userId != _deletionOwner ||
        !cloudBackupReady) {
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

    _userId = null;
    _sessionExpiryTimer?.cancel();
    _sessionExpiryTimer = null;
    _deletionCodeSent = false;
    _deletionOwner = null;
    _deletionEmail = null;
    notifyListeners();
    try {
      await _api.deleteAccountOnServer(owner);
      _notice =
          'Account deletion confirmed. Cloud workout history was '
          'deleted. This device is locked; existing local data is not '
          'automatically reassigned to another account.';
      try {
        await _api.signOutLocally();
      } catch (_) {
        // Server-side deletion is already verified. Local binding is gone.
      }
    } catch (_) {
      // Network errors may have happened AFTER the server committed deletion.
      _error =
          'Account deletion could not be confirmed. This device is '
          'locked. If the account still exists, sign in again with the '
          'same email to review it. Otherwise contact support.';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> requestCode(String email) async {
    if (_busy) return;
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
      await _api.sendEmailCode(normalized);
      _pendingEmail = normalized;
      _codeSent = true;
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
    if (_busy || _pendingEmail == null) return;
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
      // Never expose an account's ObjectBox directory before a durable
      // secure binding succeeds, even if Supabase signed in successfully.
      try {
        await _binding.write(identity);
      } catch (_) {
        // The code is spent, so send the user back to request a new one.
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
      _error = 'Verification failed. Check the code and try again.';
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
