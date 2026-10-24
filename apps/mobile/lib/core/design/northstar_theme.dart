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
  static const sleepSoftDark = Color(0xFF2D2546);
  static const sleepSoftLight = Color(0xFFEEE8FB);
  static const forestSoftDark = Color(0xFF303F26);
  static const forestSoftLight = Color(0xFFE2EEDC);
  static const heroDark = Color(0xFF101A14);
  static const heroLight = Color(0xFF152A20);
  static const heroBorder = Color(0xFF334C39);
}

class NorthstarTheme {
  const NorthstarTheme._();

  static OutlineInputBorder _fieldBorder(Color color, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: color == Colors.transparent
            ? BorderSide.none
            : BorderSide(color: color, width: width),
      );

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
    final soft = dark ? NorthstarPalette.darkSoft : NorthstarPalette.lightSoft;
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
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: border),
          borderRadius: BorderRadius.circular(22),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: soft,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        labelStyle: TextStyle(color: muted),
        floatingLabelStyle: TextStyle(
          color: accent,
          fontWeight: FontWeight.w700,
        ),
        hintStyle: TextStyle(color: muted),
        border: _fieldBorder(Colors.transparent),
        enabledBorder: _fieldBorder(Colors.transparent),
        disabledBorder: _fieldBorder(Colors.transparent),
        focusedBorder: _fieldBorder(accent, width: 1.5),
        errorBorder: _fieldBorder(scheme.error),
        focusedErrorBorder: _fieldBorder(scheme.error, width: 1.5),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: BorderSide(color: border),
        ),
        titleTextStyle: TextStyle(
          color: ink,
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.6,
        ),
        contentTextStyle: TextStyle(color: muted, fontSize: 14, height: 1.45),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        selectedColor: dark
            ? NorthstarPalette.forestSoftDark
            : NorthstarPalette.forestSoftLight,
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        labelStyle: TextStyle(color: ink, fontWeight: FontWeight.w700),
        showCheckmark: false,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: dark
            ? NorthstarPalette.darkSoft
            : NorthstarPalette.heroLight,
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: border),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 46),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 46),
          side: BorderSide(color: border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(44, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: canvas,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        toolbarHeight: 64,
        leadingWidth: 68,
        titleTextStyle: TextStyle(
          color: ink,
          fontSize: 21,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.9,
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

extension NorthstarThemeData on ThemeData {
  /// Secondary text colour; falls back to the scheme when the NorthStar theme
  /// extension is not installed (plain test themes, embedded previews).
  Color get mutedColor =>
      extension<NorthstarColors>()?.muted ?? colorScheme.onSurfaceVariant;
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
