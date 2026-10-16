import 'package:flutter/material.dart';

class AppColors {
  static const Color background = Color(0xFF0A0A0A);
  static const Color primary = Color(0xFFFF8A00);
  static const Color primaryDark = Color(0xFFCC6E00);
  static const Color primaryLight = Color(0xFFFFA333);

  static const Color textMain = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFA3A3A3);
  static const Color textMuted = Color(0xFF6B7280);

  static const Color cardSurface = Color(0xFF141414);
  static const Color surfaceElevated = Color(0xFF1C1C1C);
  static const Color surfaceHighlight = Color(0xFF242424);
  static const Color border = Color(0xFF2A2A2A);

  static const Color success = Color(0xFF22C55E);
  static const Color successDark = Color(0xFF15803D);
  static const Color error = Color(0xFFEF4444);
  static const Color warning = Color(0xFFF59E0B);

  static const LinearGradient orangeGlow = LinearGradient(
    colors: [Color(0xFFFF8A00), Color(0xFFFF5500)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient cardGradient = LinearGradient(
    colors: [Color(0xFF181818), Color(0xFF121212)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
}

class AppTheme {
  static const List<String> _fontFallbacks = [
    'Inter',
    'Roboto',
    'Segoe UI',
    'sans-serif',
  ];

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.background,
      primaryColor: AppColors.primary,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.primary,
        onPrimary: Colors.black,
        secondary: AppColors.primaryLight,
        onSecondary: Colors.black,
        surface: AppColors.cardSurface,
        onSurface: AppColors.textMain,
        error: AppColors.error,
        onError: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textMain,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AppColors.textMain,
          fontSize: 19,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.3,
          fontFamilyFallback: _fontFallbacks,
        ),
        iconTheme: IconThemeData(color: AppColors.textMain),
      ),
      cardTheme: const CardThemeData(
        color: AppColors.cardSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
          side: BorderSide(color: AppColors.border, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.black,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 15,
            letterSpacing: 0.2,
            fontFamilyFallback: _fontFallbacks,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.border, width: 1.2),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            fontFamilyFallback: _fontFallbacks,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceElevated,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        hintStyle: const TextStyle(
          color: AppColors.textMuted,
          fontSize: 14,
          fontFamilyFallback: _fontFallbacks,
        ),
        labelStyle: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 14,
          fontFamilyFallback: _fontFallbacks,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.cardSurface,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textSecondary,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          color: AppColors.textMain,
          fontWeight: FontWeight.w800,
          fontSize: 32,
          letterSpacing: -1,
          fontFamilyFallback: _fontFallbacks,
        ),
        displayMedium: TextStyle(
          color: AppColors.textMain,
          fontWeight: FontWeight.w700,
          fontSize: 26,
          letterSpacing: -0.6,
          fontFamilyFallback: _fontFallbacks,
        ),
        titleLarge: TextStyle(
          color: AppColors.textMain,
          fontWeight: FontWeight.w700,
          fontSize: 20,
          letterSpacing: -0.3,
          fontFamilyFallback: _fontFallbacks,
        ),
        titleMedium: TextStyle(
          color: AppColors.textMain,
          fontWeight: FontWeight.w600,
          fontSize: 16,
          fontFamilyFallback: _fontFallbacks,
        ),
        bodyLarge: TextStyle(
          color: AppColors.textMain,
          fontSize: 15,
          height: 1.4,
          fontFamilyFallback: _fontFallbacks,
        ),
        bodyMedium: TextStyle(
          color: AppColors.textSecondary,
          fontSize: 13.5,
          height: 1.4,
          fontFamilyFallback: _fontFallbacks,
        ),
        labelLarge: TextStyle(
          color: AppColors.textMain,
          fontWeight: FontWeight.w600,
          fontSize: 14,
          fontFamilyFallback: _fontFallbacks,
        ),
        labelSmall: TextStyle(
          color: AppColors.textMuted,
          fontSize: 11,
          fontWeight: FontWeight.w500,
          fontFamilyFallback: _fontFallbacks,
        ),
      ),
    );
  }
}
