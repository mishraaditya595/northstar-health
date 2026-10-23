import 'package:flutter/material.dart';

class NorthstarPalette {
  const NorthstarPalette._();

  static const lime = Color(0xFFD6FF60);
  static const darkCanvas = Color(0xFF0B0F13);
  static const darkSurface = Color(0xFF171E24);
  static const darkSoft = Color(0xFF202932);
  static const darkInk = Color(0xFFF5F7F6);
  static const darkMuted = Color(0xFFA5B0B8);
  static const darkBorder = Color(0xFF34404A);
  static const lightCanvas = Color(0xFFF2F5F1);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightSoft = Color(0xFFEAF0EA);
  static const lightInk = Color(0xFF172B22);
  static const lightMuted = Color(0xFF586E62);
  static const lightBorder = Color(0xFFD7E2D8);
  static const lightPrimary = Color(0xFF316946);
  static const sleepDark = Color(0xFFC1A9FF);
  static const sleepLight = Color(0xFF6650AB);
}

class NorthstarTheme {
  const NorthstarTheme._();

  static ThemeData build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final canvas = dark
        ? NorthstarPalette.darkCanvas
        : NorthstarPalette.lightCanvas;
    final surface = dark
        ? NorthstarPalette.darkSurface
        : NorthstarPalette.lightSurface;
    final ink = dark ? NorthstarPalette.darkInk : NorthstarPalette.lightInk;
    final accent = dark ? NorthstarPalette.lime : NorthstarPalette.lightPrimary;
    final muted = dark
        ? NorthstarPalette.darkMuted
        : NorthstarPalette.lightMuted;
    final border = dark
        ? NorthstarPalette.darkBorder
        : NorthstarPalette.lightBorder;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: accent,
          brightness: brightness,
          surface: surface,
        ).copyWith(
          primary: accent,
          onPrimary: dark ? NorthstarPalette.darkCanvas : Colors.white,
          onSurface: ink,
          outline: border,
        );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: canvas,
      colorScheme: scheme,
      textTheme: const TextTheme().apply(bodyColor: ink, displayColor: ink),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: border),
          borderRadius: BorderRadius.circular(22),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: dark
            ? const Color(0xFF303F26)
            : const Color(0xFFDBEBCD),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: surface,
        indicatorColor: dark
            ? const Color(0xFF303F26)
            : const Color(0xFFDBEBCD),
      ),
      dividerColor: border,
      extensions: <ThemeExtension<dynamic>>[
        NorthstarColors(muted: muted, border: border),
      ],
    );
  }
}

@immutable
class NorthstarColors extends ThemeExtension<NorthstarColors> {
  const NorthstarColors({required this.muted, required this.border});

  final Color muted;
  final Color border;

  @override
  NorthstarColors copyWith({Color? muted, Color? border}) => NorthstarColors(
    muted: muted ?? this.muted,
    border: border ?? this.border,
  );

  @override
  NorthstarColors lerp(ThemeExtension<NorthstarColors>? other, double t) {
    if (other is! NorthstarColors) return this;
    return NorthstarColors(
      muted: Color.lerp(muted, other.muted, t) ?? muted,
      border: Color.lerp(border, other.border, t) ?? border,
    );
  }
}
