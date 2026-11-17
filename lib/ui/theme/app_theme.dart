import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:network_suite_shared/network_suite_shared.dart';
import 'package:sqlite3/sqlite3.dart';

/// Adds theme mode persistence helpers on [SharedDeviceDatabase] using the
/// shared `suite_settings` table inside `shared_devices.db`.
extension SharedDeviceDatabaseThemeExt on SharedDeviceDatabase {
  static String _inMemoryThemeMode = 'dark';

  /// Reads the global suite theme mode (`'dark'` or `'light'`), defaulting to
  /// `'dark'` when uninitialized, in-memory, or before the table exists.
  Future<String> getThemeMode() async {
    if (!isInitialized || databasePath == null || databasePath == ':memory:') {
      return _inMemoryThemeMode;
    }

    final dbFile = File(databasePath!);
    if (!dbFile.existsSync()) {
      return _inMemoryThemeMode;
    }

    Database? db;
    try {
      db = sqlite3.open(databasePath!);
      db.execute('PRAGMA busy_timeout = 5000;');
      final rows = db.select(
        "SELECT value FROM suite_settings WHERE key = 'theme_mode' LIMIT 1;",
      );
      if (rows.isEmpty) return 'dark';
      return rows.first['value'] == 'light' ? 'light' : 'dark';
    } catch (_) {
      return _inMemoryThemeMode;
    } finally {
      db?.close();
    }
  }

  /// Persists the global suite theme mode (`'dark'` or `'light'`) and notifies
  /// listeners via [SharedDeviceDatabase.notifyChanged].
  Future<void> setThemeMode(String mode) async {
    if (mode != 'dark' && mode != 'light') {
      throw ArgumentError.value(mode, 'mode', "must be 'dark' or 'light'");
    }

    _inMemoryThemeMode = mode;

    if (isInitialized && databasePath != null && databasePath != ':memory:') {
      Database? db;
      try {
        db = sqlite3.open(databasePath!);
        db.execute('PRAGMA busy_timeout = 5000;');
        db.execute(
          'CREATE TABLE IF NOT EXISTS suite_settings ('
          'key TEXT PRIMARY KEY NOT NULL, '
          'value TEXT NOT NULL, '
          'updated_at TEXT NOT NULL'
          ');',
        );
        db.execute(
          "INSERT OR REPLACE INTO suite_settings (key, value, updated_at) VALUES ('theme_mode', ?, ?);",
          [mode, DateTime.now().toUtc().toIso8601String()],
        );
      } finally {
        db?.close();
      }
    }

    notifyChanged();
  }
}

/// Application color tokens and [ThemeData] builders supporting synchronized
/// dark (VS Code Slate) and light (Clean Technical Slate) modes.
class AppTheme {
  AppTheme._();

  /// Runtime dark/light state synchronized with [SharedDeviceDatabase].
  static bool isDark = true;

  /// Active theme mode string (`'dark'` or `'light'`).
  static String get themeMode => isDark ? 'dark' : 'light';

  /// Updates [isDark] from a persisted theme mode string.
  static void applyThemeMode(String mode) => isDark = (mode != 'light');

  // --- Surface & Structural Tokens ---
  static Color get scaffoldBg =>
      isDark ? const Color(0xFF141414) : const Color(0xFFF3F4F6);

  static Color get surface =>
      isDark ? const Color(0xFF1E1E1E) : const Color(0xFFFFFFFF);

  static Color get surfaceHigh =>
      isDark ? const Color(0xFF252526) : const Color(0xFFF9FAFB);

  static Color get surfaceElevated =>
      isDark ? const Color(0xFF2D2D2D) : const Color(0xFFFFFFFF);

  static Color get border =>
      isDark ? const Color(0xFF2C2C2C) : const Color(0xFFE5E7EB);

  static Color get inputBorder =>
      isDark ? const Color(0xFF3E3E42) : const Color(0xFFD1D5DB);

  // --- Typography Tokens ---
  static Color get textPrimary =>
      isDark ? const Color(0xFFE0E0E0) : const Color(0xFF111827);

  static Color get textSecondary =>
      isDark ? const Color(0xFF9E9E9E) : const Color(0xFF4B5563);

  static Color get textMuted =>
      isDark ? const Color(0xFF6E6E6E) : const Color(0xFF6B7280);

  // --- Semantic & Action Tokens ---
  static Color get accent =>
      isDark ? const Color(0xFF007ACC) : const Color(0xFF0284C7);

  static Color get success =>
      isDark ? const Color(0xFF10B981) : const Color(0xFF059669);

  static Color get error =>
      isDark ? const Color(0xFFEF4444) : const Color(0xFFDC2626);

  static Color get warning =>
      isDark ? const Color(0xFFF59E0B) : const Color(0xFFD97706);

  static Color get info =>
      isDark ? const Color(0xFF3B82F6) : const Color(0xFF2563EB);

  // --- ThemeData Builders ---
  static ThemeData get currentTheme => isDark ? darkTheme() : lightTheme();

  static ThemeData darkTheme() => _buildTheme(Brightness.dark);

  static ThemeData lightTheme() => _buildTheme(Brightness.light);

  static ThemeData _buildTheme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scaffoldBgColor =
        dark ? const Color(0xFF141414) : const Color(0xFFF3F4F6);
    final surfaceColor =
        dark ? const Color(0xFF1E1E1E) : const Color(0xFFFFFFFF);
    final surfaceHighColor =
        dark ? const Color(0xFF252526) : const Color(0xFFF9FAFB);
    final surfaceElevatedColor =
        dark ? const Color(0xFF2D2D2D) : const Color(0xFFFFFFFF);
    final borderColor =
        dark ? const Color(0xFF2C2C2C) : const Color(0xFFE5E7EB);
    final inputBorderColor =
        dark ? const Color(0xFF3E3E42) : const Color(0xFFD1D5DB);
    final textPrimaryColor =
        dark ? const Color(0xFFE0E0E0) : const Color(0xFF111827);
    final textSecondaryColor =
        dark ? const Color(0xFF9E9E9E) : const Color(0xFF4B5563);
    final accentColor =
        dark ? const Color(0xFF007ACC) : const Color(0xFF0284C7);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: accentColor,
        brightness: brightness,
        surface: surfaceColor,
        onSurface: textPrimaryColor,
        onSurfaceVariant: textSecondaryColor,
        surfaceContainerLowest:
            dark ? const Color(0xFF141414) : const Color(0xFFFFFFFF),
        surfaceContainerLow:
            dark ? const Color(0xFF1A1A1A) : const Color(0xFFF9FAFB),
        surfaceContainer:
            dark ? const Color(0xFF222222) : const Color(0xFFF3F4F6),
        surfaceContainerHigh:
            dark ? const Color(0xFF282828) : const Color(0xFFF3F4F6),
        surfaceContainerHighest:
            dark ? const Color(0xFF323232) : const Color(0xFFE5E7EB),
      ),
      scaffoldBackgroundColor: scaffoldBgColor,
      dividerColor: borderColor,
      cardTheme: CardThemeData(
        color: surfaceColor,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: borderColor),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: borderColor,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: surfaceHighColor,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: inputBorderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: inputBorderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: accentColor, width: 1.5),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceElevatedColor,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: borderColor),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surfaceElevatedColor,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: borderColor),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceElevatedColor,
        contentTextStyle: TextStyle(color: textPrimaryColor, fontSize: 13),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          side: WidgetStateProperty.resolveWith((states) {
            final color = states.contains(WidgetState.disabled)
                ? borderColor
                : inputBorderColor;
            return BorderSide(color: color);
          }),
        ),
      ),
      visualDensity: VisualDensity.compact,
    );
  }
}
