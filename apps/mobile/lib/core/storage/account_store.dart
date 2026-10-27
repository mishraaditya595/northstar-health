import 'dart:io';

import 'package:objectbox_flutter_libs/objectbox_flutter_libs.dart';

import '../../objectbox.g.dart';

final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

/// Account IDs name storage directories, so only lowercase UUIDs pass.
String validAccountId(String value) {
  final id = value.toLowerCase();
  if (!_uuid.hasMatch(id)) {
    throw const FormatException('Invalid account identifier');
  }
  return id;
}

String accountStoreRelativePath(
  String accountId, {
  required String projectHost,
}) {
  final host = projectHost.toLowerCase();
  if (!RegExp(r'^[a-z0-9.-]+$').hasMatch(host)) {
    throw const FormatException('Invalid backend host');
  }
  return 'northstar_accounts/$host/${validAccountId(accountId)}';
}

/// Only opens a *distinct* ObjectBox Store for a UUID returned by a verified
/// Supabase sign-in or a previously securely bound offline account.
/// The pre-P2-02 root ObjectBox Store is never opened or auto-associated.
Future<Store> openBoundAccountStore(
  String accountId, {
  required String projectHost,
}) async {
  final base = await defaultStoreDirectory();
  final path =
      '${base.path}/${accountStoreRelativePath(accountId, projectHost: projectHost)}';
  await Directory(path).create(recursive: true);
  return openStore(directory: path);
}

/// Erases only the confirmed-deleted owner's ObjectBox directory. The caller
/// must first unmount and close that owner's Store. This never creates a Store
/// or touches another owner's files. A missing directory is already erased.
Future<void> deleteBoundAccountStore(
  String accountId, {
  required String projectHost,
}) async {
  final base = await defaultStoreDirectory();
  await deleteBoundAccountStoreAtRoot(
    base,
    accountId,
    projectHost: projectHost,
  );
}

/// Pure filesystem boundary, allowing real directory-isolation tests without
/// opening an ObjectBox database or relying on a native device.
Future<void> deleteBoundAccountStoreAtRoot(
  Directory base,
  String accountId, {
  required String projectHost,
}) async {
  final relative = accountStoreRelativePath(
    accountId,
    projectHost: projectHost,
  );
  final directory = Directory('${base.path}/$relative');
  if (await directory.exists()) {
    await directory.delete(recursive: true);
  }
}
