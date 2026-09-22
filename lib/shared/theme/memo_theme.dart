import 'package:flutter/material.dart';

class MemoPalette {
  const MemoPalette({
    required this.background,
    required this.surface,
    required this.surfaceMuted,
    required this.hero,
    required this.text,
    required this.textMuted,
    required this.outline,
    required this.primary,
    required this.primaryDark,
    required this.secondary,
    required this.secondaryContainer,
    required this.success,
    required this.warning,
    required this.error,
    required this.aiAccent,
    required this.aiContainer,
  });

  final Color background;
  final Color surface;
  final Color surfaceMuted;
  final Color hero;
  final Color text;
  final Color textMuted;
  final Color outline;
  final Color primary;
  final Color primaryDark;
  final Color secondary;
  final Color secondaryContainer;
  final Color success;
  final Color warning;
  final Color error;
  final Color aiAccent;
  final Color aiContainer;

  static const light = MemoPalette(
    background: Color(0xFFF8FAFC),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFF1F5F9),
    hero: Color(0xFFEEF2FF),
    text: Color(0xFF0F172A),
    textMuted: Color(0xFF475569),
    outline: Color(0xFFCBD5E1),
    primary: Color(0xFF4F46E5),
    primaryDark: Color(0xFF3730A3),
    secondary: Color(0xFF0F766E),
    secondaryContainer: Color(0xFFCCFBF1),
    success: Color(0xFF15803D),
    warning: Color(0xFFB45309),
    error: Color(0xFFB91C1C),
    aiAccent: Color(0xFF7C3AED),
    aiContainer: Color(0xFFF3E8FF),
  );

  static const dark = MemoPalette(
    background: Color(0xFF0B1020),
    surface: Color(0xFF12182A),
    surfaceMuted: Color(0xFF1E293B),
    hero: Color(0xFF312E81),
    text: Color(0xFFF8FAFC),
    textMuted: Color(0xFFCBD5E1),
    outline: Color(0xFF334155),
    primary: Color(0xFFA5B4FC),
    primaryDark: Color(0xFFC7D2FE),
    secondary: Color(0xFF5EEAD4),
    secondaryContainer: Color(0xFF134E4A),
    success: Color(0xFF86EFAC),
    warning: Color(0xFFFCD34D),
    error: Color(0xFFFCA5A5),
    aiAccent: Color(0xFFD8B4FE),
    aiContainer: Color(0xFF3B245D),
  );

  static MemoPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;

  static Color deckPastel(BuildContext context, int index) {
    const lightTones = [
      Color(0xFFE0E7FF),
      Color(0xFFCCFBF1),
      Color(0xFFDBEAFE),
      Color(0xFFFEF3C7),
      Color(0xFFFFE4E6),
      Color(0xFFF3E8FF),
    ];
    const darkTones = [
      Color(0xFF312E81),
      Color(0xFF134E4A),
      Color(0xFF1E3A8A),
      Color(0xFF78350F),
      Color(0xFF881337),
      Color(0xFF581C87),
    ];
    final tones = Theme.of(context).brightness == Brightness.dark
        ? darkTones
        : lightTones;
    return tones[index % tones.length];
  }
}

class MemoTheme {
  static ThemeData get light => _build(MemoPalette.light, Brightness.light);

  static ThemeData get dark => _build(MemoPalette.dark, Brightness.dark);

  static ThemeData _build(MemoPalette p, Brightness brightness) {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: p.primary,
          brightness: brightness,
        ).copyWith(
          primary: p.primary,
          onPrimary: brightness == Brightness.light
              ? Colors.white
              : const Color(0xFF111827),
          primaryContainer: p.hero,
          onPrimaryContainer: p.text,
          secondary: p.secondary,
          onSecondary: brightness == Brightness.light
              ? Colors.white
              : const Color(0xFF052E2B),
          secondaryContainer: p.secondaryContainer,
          surface: p.surface,
          onSurface: p.text,
          outline: p.outline,
          error: p.error,
        );

    const font = 'BeVietnamPro';
    final textTheme = TextTheme(
      titleLarge: TextStyle(
        fontFamily: font,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        height: 1.4,
        color: p.text,
      ),
      headlineSmall: TextStyle(
        fontFamily: font,
        fontSize: 24,
        fontWeight: FontWeight.w700,
        height: 1.33,
        color: p.text,
      ),
      headlineMedium: TextStyle(
        fontFamily: font,
        fontSize: 32,
        fontWeight: FontWeight.w700,
        height: 1.25,
        color: p.text,
      ),
      titleMedium: TextStyle(
        fontFamily: font,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        height: 1.45,
        color: p.text,
      ),
      titleSmall: TextStyle(
        fontFamily: font,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        height: 1.5,
        color: p.text,
      ),
      bodyMedium: TextStyle(
        fontFamily: font,
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.5,
        color: p.text,
      ),
      bodySmall: TextStyle(
        fontFamily: font,
        fontSize: 13,
        fontWeight: FontWeight.w400,
        height: 1.46,
        color: p.textMuted,
      ),
      labelLarge: TextStyle(
        fontFamily: font,
        fontSize: 15,
        fontWeight: FontWeight.w600,
        height: 1.33,
        color: p.text,
      ),
      labelSmall: TextStyle(
        fontFamily: font,
        fontSize: 12,
        fontWeight: FontWeight.w500,
        height: 1.42,
        color: p.textMuted,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: p.background,
      fontFamily: font,
      textTheme: textTheme,
      splashFactory: InkRipple.splashFactory,
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.primary,
          foregroundColor: scheme.onPrimary,
          minimumSize: const Size(0, 52),
          textStyle: textTheme.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}
