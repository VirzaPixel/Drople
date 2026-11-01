import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Token visual Drople: dark utility surface dengan aksen cyan.
class AppColors {
  AppColors._();

  static const background = Color(0xFF0A0E1A);
  static const surface = Color(0xFF0F1524);
  static const surfaceContainerLowest = Color(0xFF080B15);
  static const surfaceContainer = Color(0xFF141C2E);
  static const surfaceContainerHigh = Color(0xFF1A2438);
  static const surfaceContainerHighest = Color(0xFF202C42);
  static const primary = Color(0xFF7DD3FC);
  static const onPrimary = Color(0xFF001F2E);
  static const onSurface = Color(0xFFE0E8F0);
  static const onSurfaceVariant = Color(0xFFA0B4C4);
  static const amber = Color(0xFFF4B860);
  static const danger = Color(0xFFFF6B6B);

  // Alias lama yang masih dipakai layar/komponen.
  static const ink = onSurface;
  static const mist = background;
  static const paper = surface;
  static const leaf = primary;
  static const leafDeep = Color(0xFF38BDF8);
  static const line = surfaceContainerHigh;
  static const muted = onSurfaceVariant;
  static const darkInk = background;
  static const darkSurface = surface;
  static const darkLine = surfaceContainerHigh;
  static const darkMuted = onSurfaceVariant;
}

extension ColorOpacityX on Color {
  Color o(double opacity) => withValues(alpha: opacity);
}

TextStyle inter(
  double size, {
  FontWeight weight = FontWeight.w400,
  Color color = AppColors.onSurface,
  double? letterSpacing,
  double? height,
}) => GoogleFonts.inter(
  fontSize: size,
  fontWeight: weight,
  color: color,
  letterSpacing: letterSpacing,
  height: height,
);

TextStyle mono(
  double size, {
  Color color = AppColors.onSurface,
  FontWeight weight = FontWeight.w400,
}) => GoogleFonts.robotoMono(fontSize: size, color: color, fontWeight: weight);

class AppTheme {
  static ThemeData dark() => _build();

  static ThemeData _build() {
    const scheme = ColorScheme.dark(
      primary: AppColors.primary,
      onPrimary: AppColors.onPrimary,
      secondary: AppColors.amber,
      onSecondary: AppColors.onPrimary,
      error: AppColors.danger,
      onError: Colors.white,
      surface: AppColors.surface,
      onSurface: AppColors.onSurface,
      surfaceContainerHighest: AppColors.surfaceContainerHighest,
      outline: AppColors.surfaceContainerHigh,
      outlineVariant: AppColors.surfaceContainerHigh,
      onSurfaceVariant: AppColors.onSurfaceVariant,
      shadow: Colors.black,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
    );

    final text = GoogleFonts.interTextTheme(base.textTheme)
        .apply(
          bodyColor: AppColors.onSurface,
          displayColor: AppColors.onSurface,
        )
        .copyWith(
          displaySmall: TextStyle(
            fontSize: 30,
            height: 1.12,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.9,
            color: AppColors.onSurface,
          ),
          headlineMedium: TextStyle(
            fontSize: 24,
            height: 1.16,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
            color: AppColors.onSurface,
          ),
          headlineSmall: TextStyle(
            fontSize: 20,
            height: 1.2,
            fontWeight: FontWeight.w700,
            color: AppColors.onSurface,
          ),
          titleLarge: TextStyle(
            fontSize: 16,
            height: 1.3,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
            color: AppColors.onSurface,
          ),
          titleMedium: TextStyle(
            fontSize: 14,
            height: 1.35,
            fontWeight: FontWeight.w600,
            color: AppColors.onSurface,
          ),
          titleSmall: TextStyle(
            fontSize: 13,
            height: 1.35,
            fontWeight: FontWeight.w600,
            color: AppColors.onSurface,
          ),
          bodyLarge: TextStyle(
            fontSize: 14,
            height: 1.6,
            color: AppColors.onSurface,
          ),
          bodyMedium: TextStyle(
            fontSize: 13,
            height: 1.55,
            color: AppColors.onSurface,
          ),
          bodySmall: TextStyle(
            fontSize: 11.5,
            height: 1.45,
            color: AppColors.onSurfaceVariant,
          ),
          labelLarge: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          labelSmall: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w500,
            color: AppColors.onSurfaceVariant,
          ),
        );

    return base.copyWith(
      textTheme: text,
      splashColor: AppColors.primary.withValues(alpha: 0.08),
      highlightColor: AppColors.primary.withValues(alpha: 0.04),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: AppColors.surfaceContainer.withValues(alpha: 0.8),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.surfaceContainerHigh),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.surfaceContainerHigh,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceContainer.withValues(alpha: 0.6),
        hintStyle: text.bodySmall,
        labelStyle: text.bodySmall,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: _inputBorder(AppColors.surfaceContainerHigh),
        enabledBorder: _inputBorder(AppColors.surfaceContainerHigh),
        focusedBorder: _inputBorder(AppColors.primary.withValues(alpha: 0.55)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.onSurface,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          side: const BorderSide(color: AppColors.surfaceContainerHigh),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface.withValues(alpha: 0.96),
        indicatorColor: AppColors.primary.withValues(alpha: 0.15),
        height: 64,
        elevation: 0,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.onSurface,
            fontFamily: GoogleFonts.inter().fontFamily,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.primary.withValues(alpha: 0.15),
        selectedLabelTextStyle: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.primary,
        ),
        unselectedLabelTextStyle: const TextStyle(
          fontSize: 11,
          color: AppColors.onSurfaceVariant,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.surfaceContainerHighest,
        contentTextStyle: const TextStyle(
          color: AppColors.onSurface,
          fontSize: 12,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        insetPadding: const EdgeInsets.all(16),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceContainer.withValues(alpha: 0.5),
        selectedColor: AppColors.surfaceContainerHighest,
        side: const BorderSide(color: AppColors.surfaceContainerHigh),
        labelStyle: const TextStyle(fontSize: 12, color: AppColors.onSurface),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: text.titleLarge,
        contentTextStyle: text.bodyMedium,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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

  static OutlineInputBorder _inputBorder(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(color: color),
  );
}
