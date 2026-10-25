import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Persists Supabase session credentials in OS-protected storage, not
/// SharedPreferences, ObjectBox, files, analytics, or application logs.
class NorthstarSecureSessionStorage extends LocalStorage {
  NorthstarSecureSessionStorage({required String projectHost})
    : _key = 'northstar.supabase.session.v1.$projectHost';

  final String _key;
  static const _storage = FlutterSecureStorage();

  @override
  Future<void> initialize() async {}

  @override
  Future<String?> accessToken() => _storage.read(key: _key);

  @override
  Future<bool> hasAccessToken() => _storage.containsKey(key: _key);

  @override
  Future<void> persistSession(String session) =>
      _storage.write(key: _key, value: session);

  @override
  Future<void> removePersistedSession() => _storage.delete(key: _key);
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
  static const _storage = FlutterSecureStorage();

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String userId) => _storage.write(key: _key, value: userId);

  @override
  Future<void> clear() => _storage.delete(key: _key);
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

  static final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );

  static String validUserId(String value) {
    final id = value.toLowerCase();
    if (!_uuid.hasMatch(id)) {
      throw const FormatException('Invalid account identifier');
    }
    return id;
  }

  /// Called only after Supabase has restored its securely persisted session.
  /// If an online SDK session belongs to a different account, no partition
  /// is opened: explicit reauthentication is required.
  Future<void> restore() async {
    final bound = await _binding.read();
    final active = _api.signedInUserId;
    if (bound != null) {
      final verifiedBound = validUserId(bound);
      if (active == null ||
          (!_api.isAnonymous && validUserId(active) == verifiedBound)) {
        _userId = verifiedBound;
      }
    }
    notifyListeners();
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
      final identity = validUserId(
        await _api.verifyEmailCode(_pendingEmail!, code),
      );
      // Never expose an account's ObjectBox directory before a durable
      // secure binding succeeds, even if Supabase signed in successfully.
      await _binding.write(identity);
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
      _userId = null;
      _codeSent = false;
      _pendingEmail = null;
      notifyListeners();
      await _api.signOutLocally();
    } catch (_) {
      _error = 'Could not finish signing out. Retry before sharing the device.';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}
