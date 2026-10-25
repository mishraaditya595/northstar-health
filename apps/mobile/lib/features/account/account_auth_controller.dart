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

  Future<void> sendEmailCode(String email);
  Future<String> verifyEmailCode(String email, String code);
  Future<void> signOutLocally();
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
}

/// No listener ever receives credentials. A prior online verification writes
/// the bound user ID into OS secure storage. When a token refresh cannot run
/// offline, only that same account may open its partitioned local database.
class AccountAuthController extends ChangeNotifier {
  AccountAuthController(this._api, this._binding);

  final AccountAuthApi _api;
  final BoundAccountStore _binding;

  String? _userId;
  bool _busy = false;
  bool _codeSent = false;
  String? _error;
  String? _pendingEmail;

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
    _codeSent = false;
    _pendingEmail = null;
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
}
