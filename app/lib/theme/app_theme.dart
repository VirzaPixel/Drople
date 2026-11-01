import 'package:flutter/material.dart';

class AppColors {
  static const ink = Color(0xFF16211D);
  static const mist = Color(0xFFF3F5F0);
  static const paper = Color(0xFFFFFFFF);
  static const leaf = Color(0xFF186B58);
  static const leafDeep = Color(0xFF0E4C3F);
  static const amber = Color(0xFFD9822B);
  static const line = Color(0xFFE2E6DD);
  static const muted = Color(0xFF6B7770);
  static const danger = Color(0xFFB3423A);

  static const darkInk = Color(0xFF0D1412);
  static const darkSurface = Color(0xFF16201C);
  static const darkLine = Color(0xFF27332E);
  static const darkMuted = Color(0xFF9AA8A1);
}

class AppTheme {
  static ThemeData light() => _build(
        brightness: Brightness.light,
        surface: AppColors.mist,
        card: AppColors.paper,
        ink: AppColors.ink,
        muted: AppColors.muted,
        line: AppColors.line,
        primary: AppColors.leaf,
      );

  static ThemeData dark() => _build(
        brightness: Brightness.dark,
        surface: AppColors.darkInk,
        card: AppColors.darkSurface,
        ink: const Color(0xFFF2F6F1),
        muted: AppColors.darkMuted,
        line: AppColors.darkLine,
        primary: const Color(0xFF63C4A9),
      );

  static ThemeData _build({
    required Brightness brightness,
    required Color surface,
    required Color card,
    required Color ink,
    required Color muted,
    required Color line,
    required Color primary,
  }) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme(
      brightness: brightness,
      primary: primary,
      onPrimary: isDark ? const Color(0xFF06231C) : Colors.white,
      secondary: AppColors.amber,
      onSecondary: Colors.white,
      error: AppColors.danger,
      onError: Colors.white,
      surface: card,
      onSurface: ink,
      surfaceContainerHighest: isDark ? const Color(0xFF1F2B26) : const Color(0xFFECEFE8),
      outline: line,
      outlineVariant: line,
      onSurfaceVariant: muted,
      shadow: Colors.black.withValues(alpha: 0.08),
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: surface,
      fontFamily: 'Roboto',
    );

    final text = base.textTheme
        .apply(bodyColor: ink, displayColor: ink)
        .copyWith(
          displaySmall: TextStyle(
            fontSize: 34,
            height: 1.1,
            fontWeight: FontWeight.w700,
            letterSpacing: -1.1,
            color: ink,
          ),
          headlineMedium: TextStyle(
            fontSize: 26,
            height: 1.15,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.7,
            color: ink,
          ),
          titleLarge: TextStyle(
            fontSize: 19,
            height: 1.25,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
            color: ink,
          ),
          titleMedium: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: ink,
          ),
          bodyMedium: TextStyle(fontSize: 14, height: 1.5, color: ink),
          bodySmall: TextStyle(fontSize: 12.5, height: 1.4, color: muted),
          labelLarge: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        );

    return base.copyWith(
      textTheme: text,
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        foregroundColor: ink,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: line),
        ),
      ),
      dividerTheme: DividerThemeData(color: line, thickness: 1, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF1B2722) : const Color(0xFFF7F8F4),
        hintStyle: TextStyle(color: muted),
        labelStyle: TextStyle(color: muted),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: primary, width: 1.6),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          side: BorderSide(color: line),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: card,
        indicatorColor: primary.withValues(alpha: isDark ? 0.22 : 0.14),
        height: 72,
        elevation: 0,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: ink),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: card,
        indicatorColor: primary.withValues(alpha: isDark ? 0.22 : 0.14),
        selectedLabelTextStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: primary,
        ),
        unselectedLabelTextStyle: TextStyle(fontSize: 12, color: muted),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? const Color(0xFF24322C) : AppColors.ink,
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 13.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        insetPadding: const EdgeInsets.all(16),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: card,
        selectedColor: primary.withValues(alpha: isDark ? 0.24 : 0.14),
        side: BorderSide(color: line),
        labelStyle: TextStyle(fontSize: 12.5, color: ink, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: text.titleLarge,
        contentTextStyle: text.bodyMedium,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
        },
      ),
    );
  }
}
