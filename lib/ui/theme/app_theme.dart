import 'package:flutter/material.dart';

class AppTheme {
  static ThemeData darkTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF007ACC),
        brightness: Brightness.dark,
        surface: const Color(0xFF1E1E1E),
        surfaceContainerLowest: const Color(0xFF141414),
        surfaceContainerLow: const Color(0xFF1A1A1A),
        surfaceContainer: const Color(0xFF222222),
        surfaceContainerHigh: const Color(0xFF282828),
        surfaceContainerHighest: const Color(0xFF323232),
      ),
      scaffoldBackgroundColor: const Color(0xFF141414),
      cardTheme: const CardThemeData(
        color: Color(0xFF1E1E1E),
        elevation: 0,
        margin: EdgeInsets.zero,
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xFF2C2C2C),
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: const Color(0xFF252526),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: Color(0xFF3E3E42)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: Color(0xFF3E3E42)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: Color(0xFF007ACC), width: 1.5),
        ),
      ),
      visualDensity: VisualDensity.compact,
    );
  }
}
