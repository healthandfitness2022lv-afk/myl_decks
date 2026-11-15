// lib/theme/app_theme.dart
// Tema centralizado de MyL Mazos.
//
// Única fuente de verdad para la paleta. Las pantallas nuevas deben usar
// estas constantes (o Theme.of(context)) en lugar de hardcodear colores.
import 'package:flutter/material.dart';

/// Paleta de la app (los mismos tonos que ya usa la UI).
abstract class AppColors {
  // Fondos
  static const bg = Color(0xFF0D1016); // scaffold
  static const surface = Color(0xFF12161D); // cards / paneles
  static const surfaceAlt = Color(0xFF14181F); // appbar / barras
  static const surfaceDeep = Color(0xFF0E1117); // pozos / imagen vacía

  // Acento dorado (identidad MyL)
  static const gold = Color(0xFFF1D48B);
  static const goldStrong = Color(0xFFD9A323);
  static const goldSoft = Color(0xFFF2D487);

  // Texto
  static const text = Colors.white;
  static const textSecondary = Colors.white70;
  static const textFaint = Colors.white54;

  // Bordes
  static const border = Colors.white10;
  static const borderStrong = Colors.white24;

  // Estados
  static const success = Color(0xFF4CAF50);
  static const danger = Color(0xFFE57373);
  static const warning = Color(0xFFF59E0B);
  static const info = Color(0xFF4FC3F7);
}

abstract class AppTheme {
  static ThemeData get dark {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.gold,
      brightness: Brightness.dark,
      surface: AppColors.surface,
      primary: AppColors.gold,
      onPrimary: const Color(0xFF14181F),
      secondary: AppColors.goldStrong,
      error: AppColors.danger,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.bg,
      canvasColor: AppColors.surface,

      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.surfaceAlt,
        foregroundColor: AppColors.text,
        centerTitle: true,
        elevation: 0,
        titleTextStyle: TextStyle(
          color: AppColors.gold,
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
      ),

      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border),
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: const TextStyle(
          color: AppColors.text,
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
        contentTextStyle: const TextStyle(color: AppColors.textSecondary),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceDeep,
        hintStyle: const TextStyle(color: AppColors.textFaint),
        labelStyle: const TextStyle(color: AppColors.textSecondary),
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
          borderSide: const BorderSide(color: AppColors.gold),
        ),
        isDense: true,
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.gold,
          foregroundColor: const Color(0xFF14181F),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.gold,
          foregroundColor: const Color(0xFF14181F),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.gold),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.gold,
          side: const BorderSide(color: AppColors.borderStrong),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),

      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.gold,
        foregroundColor: Color(0xFF14181F),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceDeep,
        selectedColor: AppColors.gold.withOpacity(.2),
        labelStyle: const TextStyle(color: AppColors.textSecondary),
        side: const BorderSide(color: AppColors.borderStrong),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),

      snackBarTheme: const SnackBarThemeData(
        backgroundColor: AppColors.surfaceAlt,
        contentTextStyle: TextStyle(color: AppColors.text),
        behavior: SnackBarBehavior.floating,
      ),

      dividerTheme: const DividerThemeData(color: AppColors.border),

      listTileTheme: const ListTileThemeData(
        textColor: AppColors.text,
        iconColor: AppColors.textSecondary,
      ),

      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.gold,
      ),

      tabBarTheme: const TabBarThemeData(
        labelColor: AppColors.gold,
        unselectedLabelColor: AppColors.textFaint,
        indicatorColor: AppColors.gold,
      ),

      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
    );
  }
}
