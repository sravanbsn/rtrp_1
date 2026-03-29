import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Drishti-Link Design Tokens
/// Dark navy + saffron palette — high contrast for accessibility
abstract class AppColors {
  // Backgrounds
  static const Color navyDeep = Color(0xFF050A1E);
  static const Color navyMid = Color(0xFF0A0E2E);
  static const Color navyLight = Color(0xFF141A3D);
  static const Color navyCard = Color(0xFF1A2050);

  // Saffron accent (Indian flag inspired)
  static const Color saffron = Color(0xFFFF9933);
  static const Color saffronLight = Color(0xFFFFB366);
  static const Color saffronDark = Color(0xFFD4771A);
  static const Color saffronGlow = Color(0x40FF9933);

  // Text
  static const Color white = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFB0B8D4);
  static const Color textMuted = Color(0xFF6B7399);

  // Orb / glow
  static const Color orbCore = Color(0xFFFFB366);
  static const Color orbMid = Color(0x60FF9933);
  static const Color orbOuter = Color(0x20FF6600);

  // Semantic
  static const Color hazardRed = Color(0xFFFF4444);
  static const Color safeGreen = Color(0xFF44FF88);
}

abstract class AppDurations {
  static const Duration fast = Duration(milliseconds: 200);
  static const Duration medium = Duration(milliseconds: 400);
  static const Duration slow = Duration(milliseconds: 700);
  static const Duration splash = Duration(seconds: 3);
}

abstract class AppSizes {
  /// Minimum touch target — WCAG 2.1 AA
  static const double minTouchTarget = 56.0;
  static const double buttonRadius = 16.0;
  static const double cardRadius = 20.0;

  // Spacing
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 16.0;
  static const double lg = 24.0;
  static const double xl = 32.0;
  static const double xxl = 48.0;
}

class AppTheme {
  AppTheme._();

  static ThemeData dark() {
    final base = ThemeData.dark();
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.navyMid,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.saffron,
        secondary: AppColors.saffronLight,
        surface: AppColors.navyCard,
        error: AppColors.hazardRed,
        onPrimary: AppColors.navyDeep,
        onSurface: AppColors.white,
      ),
      textTheme: _buildTextTheme(),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.saffron,
          foregroundColor: AppColors.navyDeep,
          minimumSize: const Size(double.infinity, AppSizes.minTouchTarget),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSizes.buttonRadius),
          ),
          textStyle: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
          elevation: 0,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.textSecondary,
          minimumSize:
              const Size(AppSizes.minTouchTarget, AppSizes.minTouchTarget),
          textStyle: GoogleFonts.nunito(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }

  static TextTheme _buildTextTheme() {
    return TextTheme(
      // Headlines
      displayLarge: GoogleFonts.poppins(
        fontSize: 40,
        fontWeight: FontWeight.w700,
        color: AppColors.white,
        height: 1.1,
      ),
      displayMedium: GoogleFonts.poppins(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        color: AppColors.white,
        height: 1.2,
      ),
      headlineLarge: GoogleFonts.poppins(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: AppColors.white,
        height: 1.2,
      ),
      headlineMedium: GoogleFonts.poppins(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: AppColors.white,
      ),
      // Body
      bodyLarge: GoogleFonts.nunito(
        fontSize: 18,
        fontWeight: FontWeight.w400,
        color: AppColors.textSecondary,
        height: 1.6,
      ),
      bodyMedium: GoogleFonts.nunito(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: AppColors.textSecondary,
        height: 1.5,
      ),
      // Labels / buttons
      labelLarge: GoogleFonts.poppins(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: AppColors.navyDeep,
        letterSpacing: 0.3,
      ),
    );
  }
}
