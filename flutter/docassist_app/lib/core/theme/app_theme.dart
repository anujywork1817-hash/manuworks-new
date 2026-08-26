import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ─── Colors ───────────────────────────────────────────────────────────────────

class AppColors {
  AppColors._();

  // Primary — pure black / white depending on theme
  static const primary         = Color(0xFF0A0A0A);
  static const primaryLight    = Color(0xFF1A1A1A);
  static const primaryDark     = Color(0xFF000000);
  static const primaryContainer = Color(0xFFF3F3F3);

  // Secondary
  static const secondary          = Color(0xFF1A1A1A);
  static const secondaryLight     = Color(0xFF404040);
  static const secondaryContainer = Color(0xFFF5F5F5);

  // Accent — kept for AI/success indicators; very subtle
  static const accent          = Color(0xFF0A0A0A);
  static const accentLight     = Color(0xFF404040);
  static const accentContainer = Color(0xFFF3F3F3);

  // Semantic
  static const error            = Color(0xFFDC2626);
  static const errorContainer   = Color(0xFFFEF2F2);
  static const warning          = Color(0xFFD97706);
  static const warningContainer = Color(0xFFFFFBEB);
  static const success          = Color(0xFF16A34A);
  static const successContainer = Color(0xFFF0FDF4);
  static const info             = Color(0xFF2563EB);
  static const infoContainer    = Color(0xFFEFF6FF);

  // Neutrals — Light theme
  static const surface         = Color(0xFFFFFFFF);
  static const surfaceVariant  = Color(0xFFF9F9F9);
  static const background      = Color(0xFFFFFFFF);
  static const outline         = Color(0xFFE5E5E5);
  static const outlineVariant  = Color(0xFFF3F3F3);

  // Text — Light theme
  static const textPrimary    = Color(0xFF0A0A0A);
  static const textSecondary  = Color(0xFF525252);
  static const textTertiary   = Color(0xFFA3A3A3);
  static const textDisabled   = Color(0xFFD4D4D4);
  static const textOnPrimary  = Color(0xFFFFFFFF);

  // Dark theme surfaces
  static const darkSurface        = Color(0xFF1A1A1A);
  static const darkSurfaceVariant = Color(0xFF141414);
  static const darkBackground     = Color(0xFF0A0A0A);
  static const darkOutline        = Color(0xFF2E2E2E);
  static const darkTextPrimary    = Color(0xFFF5F5F5);
  static const darkTextSecondary  = Color(0xFFA3A3A3);
  static const darkTextTertiary   = Color(0xFF666666);

  // Document type chips — kept as functional color codes
  static const pdfColor   = Color(0xFFDC2626);
  static const docxColor  = Color(0xFF2563EB);
  static const txtColor   = Color(0xFF737373);
  static const imageColor = Color(0xFF16A34A);
}

// ─── Text Styles ──────────────────────────────────────────────────────────────

class AppTextStyles {
  AppTextStyles._();

  static TextTheme get textTheme => GoogleFonts.interTextTheme().copyWith(
        displayLarge: GoogleFonts.inter(fontSize: 57, fontWeight: FontWeight.w400, color: AppColors.textPrimary),
        displayMedium: GoogleFonts.inter(fontSize: 45, fontWeight: FontWeight.w400, color: AppColors.textPrimary),
        displaySmall: GoogleFonts.inter(fontSize: 36, fontWeight: FontWeight.w400, color: AppColors.textPrimary),
        headlineLarge: GoogleFonts.inter(fontSize: 32, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        headlineMedium: GoogleFonts.inter(fontSize: 28, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        headlineSmall: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
        titleLarge: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.3, color: AppColors.textPrimary),
        titleMedium: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.2, color: AppColors.textPrimary),
        titleSmall: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: -0.1, color: AppColors.textPrimary),
        bodyLarge: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w400, color: AppColors.textPrimary),
        bodyMedium: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w400, color: AppColors.textSecondary),
        bodySmall: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w400, color: AppColors.textTertiary),
        labelLarge: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.1, color: AppColors.textPrimary),
        labelMedium: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, letterSpacing: 0.3, color: AppColors.textSecondary),
        labelSmall: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 0.4, color: AppColors.textTertiary),
      );
}

// ─── Theme Data ───────────────────────────────────────────────────────────────

class AppTheme {
  AppTheme._();

  static ThemeData get light => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: const ColorScheme.light(
          primary: AppColors.primary,
          onPrimary: AppColors.textOnPrimary,
          primaryContainer: AppColors.primaryContainer,
          onPrimaryContainer: AppColors.primary,
          secondary: AppColors.secondary,
          onSecondary: AppColors.textOnPrimary,
          secondaryContainer: AppColors.secondaryContainer,
          tertiary: AppColors.accent,
          error: AppColors.error,
          errorContainer: AppColors.errorContainer,
          surface: AppColors.surface,
          onSurface: AppColors.textPrimary,
          surfaceContainerHighest: AppColors.surfaceVariant,
          outline: AppColors.outline,
          outlineVariant: AppColors.outlineVariant,
        ),
        textTheme: AppTextStyles.textTheme,
        scaffoldBackgroundColor: AppColors.background,

        // AppBar — white, thin bottom line
        appBarTheme: AppBarTheme(
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          scrolledUnderElevation: 0,
          shadowColor: AppColors.outline,
          surfaceTintColor: Colors.transparent,
          titleTextStyle: GoogleFonts.inter(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
            color: AppColors.textPrimary,
          ),
          iconTheme: const IconThemeData(color: AppColors.textPrimary, size: 22),
        ),

        // Cards — white with hairline border
        cardTheme: const CardThemeData(
          color: AppColors.surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            side: BorderSide(color: AppColors.outline, width: 1),
          ),
          margin: EdgeInsets.zero,
        ),

        // Elevated Button — solid black
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.textOnPrimary,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),

        // Outlined Button
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            side: const BorderSide(color: AppColors.primary, width: 1.5),
            textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),

        // Text Button
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: AppColors.primary,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500),
          ),
        ),

        // Input Fields
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.surfaceVariant,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.outline)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.outline)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
          errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.error)),
          focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.error, width: 1.5)),
          hintStyle: GoogleFonts.inter(color: AppColors.textTertiary, fontSize: 14),
          labelStyle: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 14),
          errorStyle: GoogleFonts.inter(color: AppColors.error, fontSize: 12),
        ),

        // FAB — black square-ish
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.textOnPrimary,
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),

        // Bottom NavigationBar
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: AppColors.surface,
          indicatorColor: AppColors.primaryContainer,
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.transparent,
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primary);
            }
            return GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w400, color: AppColors.textTertiary);
          }),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const IconThemeData(color: AppColors.primary, size: 22);
            }
            return const IconThemeData(color: AppColors.textTertiary, size: 22);
          }),
          elevation: 0,
        ),

        // Divider
        dividerTheme: const DividerThemeData(color: AppColors.outline, thickness: 1, space: 1),

        // Chip
        chipTheme: ChipThemeData(
          backgroundColor: AppColors.surfaceVariant,
          selectedColor: AppColors.primaryContainer,
          labelStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: const BorderSide(color: AppColors.outline)),
        ),

        // SnackBar
        snackBarTheme: SnackBarThemeData(
          backgroundColor: AppColors.primary,
          contentTextStyle: GoogleFonts.inter(color: Colors.white, fontSize: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          behavior: SnackBarBehavior.floating,
        ),

        // Dialog
        dialogTheme: DialogThemeData(
          backgroundColor: AppColors.surface,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: AppColors.outline)),
          titleTextStyle: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        ),

        // List Tile
        listTileTheme: ListTileThemeData(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          tileColor: Colors.transparent,
        ),

        // Progress
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: AppColors.primary,
          linearTrackColor: AppColors.primaryContainer,
        ),

        // Switch
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.selected) ? AppColors.textOnPrimary : AppColors.textTertiary),
          trackColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.selected) ? AppColors.primary : AppColors.outlineVariant),
        ),
      );

  // ── Dark Theme ────────────────────────────────────────────────────────────
  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.darkTextPrimary,
          onPrimary: AppColors.darkBackground,
          primaryContainer: AppColors.darkOutline,
          onPrimaryContainer: AppColors.darkTextPrimary,
          secondary: AppColors.darkTextSecondary,
          onSecondary: AppColors.darkBackground,
          secondaryContainer: Color(0xFF2A2A2A),
          tertiary: AppColors.darkTextPrimary,
          error: AppColors.error,
          errorContainer: Color(0xFF3B0000),
          surface: AppColors.darkSurface,
          onSurface: AppColors.darkTextPrimary,
          surfaceContainerHighest: AppColors.darkSurfaceVariant,
          outline: AppColors.darkOutline,
          outlineVariant: Color(0xFF222222),
        ),
        textTheme: GoogleFonts.interTextTheme().copyWith(
          titleLarge: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.3, color: AppColors.darkTextPrimary),
          titleMedium: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.darkTextPrimary),
          titleSmall: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.darkTextPrimary),
          bodyLarge: GoogleFonts.inter(fontSize: 16, color: AppColors.darkTextPrimary),
          bodyMedium: GoogleFonts.inter(fontSize: 14, color: AppColors.darkTextSecondary),
          bodySmall: GoogleFonts.inter(fontSize: 12, color: AppColors.darkTextTertiary),
          labelLarge: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.darkTextPrimary),
          labelMedium: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.darkTextSecondary),
          labelSmall: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.darkTextTertiary),
        ),
        scaffoldBackgroundColor: AppColors.darkBackground,
        appBarTheme: AppBarTheme(
          backgroundColor: AppColors.darkBackground,
          foregroundColor: AppColors.darkTextPrimary,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          titleTextStyle: GoogleFonts.inter(
            fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: -0.3, color: AppColors.darkTextPrimary),
          iconTheme: const IconThemeData(color: AppColors.darkTextPrimary, size: 22),
        ),
        cardTheme: const CardThemeData(
          color: AppColors.darkSurface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            side: BorderSide(color: AppColors.darkOutline, width: 1),
          ),
          margin: EdgeInsets.zero,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.darkTextPrimary,
            foregroundColor: AppColors.darkBackground,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.darkTextPrimary,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            side: const BorderSide(color: AppColors.darkOutline, width: 1.5),
            textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: AppColors.darkTextPrimary,
            textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.darkSurfaceVariant,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.darkOutline)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.darkOutline)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.darkTextPrimary, width: 1.5)),
          errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.error)),
          focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.error, width: 1.5)),
          hintStyle: GoogleFonts.inter(color: AppColors.darkTextTertiary, fontSize: 14),
          labelStyle: GoogleFonts.inter(color: AppColors.darkTextSecondary, fontSize: 14),
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: AppColors.darkTextPrimary,
          foregroundColor: AppColors.darkBackground,
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: AppColors.darkBackground,
          indicatorColor: AppColors.darkOutline,
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.transparent,
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.darkTextPrimary);
            }
            return GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w400, color: AppColors.darkTextTertiary);
          }),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const IconThemeData(color: AppColors.darkTextPrimary, size: 22);
            }
            return const IconThemeData(color: AppColors.darkTextTertiary, size: 22);
          }),
          elevation: 0,
        ),
        dividerTheme: const DividerThemeData(color: AppColors.darkOutline, thickness: 1, space: 1),
        chipTheme: ChipThemeData(
          backgroundColor: AppColors.darkSurfaceVariant,
          selectedColor: AppColors.darkOutline,
          labelStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.darkTextPrimary),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: const BorderSide(color: AppColors.darkOutline)),
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: AppColors.darkSurface,
          contentTextStyle: GoogleFonts.inter(color: AppColors.darkTextPrimary, fontSize: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: AppColors.darkOutline)),
          behavior: SnackBarBehavior.floating,
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: AppColors.darkSurface,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: AppColors.darkOutline)),
          titleTextStyle: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.darkTextPrimary),
        ),
        listTileTheme: ListTileThemeData(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          tileColor: Colors.transparent,
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: AppColors.darkTextPrimary,
          linearTrackColor: AppColors.darkOutline,
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.selected) ? AppColors.darkBackground : AppColors.darkTextTertiary),
          trackColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.selected) ? AppColors.darkTextPrimary : AppColors.darkOutline),
        ),
      );
}

// ─── Spacing ──────────────────────────────────────────────────────────────────

class AppSpacing {
  AppSpacing._();
  static const xs  = 4.0;
  static const sm  = 8.0;
  static const md  = 16.0;
  static const lg  = 24.0;
  static const xl  = 32.0;
  static const xxl = 48.0;
}

// ─── Border Radius ────────────────────────────────────────────────────────────

class AppRadius {
  AppRadius._();
  static const sm   = BorderRadius.all(Radius.circular(8));
  static const md   = BorderRadius.all(Radius.circular(12));
  static const lg   = BorderRadius.all(Radius.circular(16));
  static const xl   = BorderRadius.all(Radius.circular(24));
  static const full = BorderRadius.all(Radius.circular(100));
}

// ─── Shadows ─────────────────────────────────────────────────────────────────

class AppShadows {
  AppShadows._();

  static List<BoxShadow> get sm => [
    BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4, offset: const Offset(0, 1)),
  ];

  static List<BoxShadow> get md => [
    BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2)),
    BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 2, offset: const Offset(0, 1)),
  ];

  static List<BoxShadow> get lg => [
    BoxShadow(color: Colors.black.withValues(alpha: 0.10), blurRadius: 20, offset: const Offset(0, 4)),
    BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2)),
  ];
}
