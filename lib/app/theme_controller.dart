import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final themeControllerProvider =
    NotifierProvider<ThemeController, ThemeMode>(ThemeController.new);

class ThemeController extends Notifier<ThemeMode> {
  static const _key = 'appearance_mode';

  @override
  ThemeMode build() {
    _load();
    return ThemeMode.system;
  }

  Future<void> _load() async {
    try {
      final preferences = SharedPreferencesAsync();
      final saved = await preferences.getString(_key);
      if (saved == 'dark') state = ThemeMode.dark;
      if (saved == 'light') state = ThemeMode.light;
    } catch (_) {
      // A preferences failure should never stop the application.
    }
  }

  Future<void> toggle(Brightness current) async {
    final next = current == Brightness.dark
        ? ThemeMode.light
        : ThemeMode.dark;
    state = next;
    try {
      await SharedPreferencesAsync().setString(_key, next.name);
    } catch (_) {
      // The selected theme remains available for this session.
    }
  }
}
