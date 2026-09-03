import 'package:flutter/material.dart';

/// Фирменная тёмная тема BridgeMesh — глубокий космический фон с бирюзовым
/// и фиолетовым неоновым акцентом. Это визуальный язык «mesh-сети».
class MeshTheme {
  static const Color background = Color(0xFF050813);
  static const Color surface = Color(0xFF0D1426);
  static const Color surfaceAlt = Color(0xFF131C36);
  static const Color primary = Color(0xFF00E5C8); // бирюзовый
  static const Color secondary = Color(0xFF7C5CFF); // фиолетовый
  static const Color accent = Color(0xFFFF4F8B); // розовый неон
  static const Color textPrimary = Color(0xFFE7ECF7);
  static const Color textSecondary = Color(0xFF8C95B5);
  static const Color danger = Color(0xFFFF5470);
  static const Color success = Color(0xFF4ADE80);

  static const LinearGradient headerGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF00E5C8), Color(0xFF7C5CFF)],
  );

  static const LinearGradient bgGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF050813), Color(0xFF0A1024), Color(0xFF0D1426)],
  );

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final base = isDark ? ThemeData.dark() : ThemeData.light();
    final cs = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: brightness,
      primary: primary,
      secondary: secondary,
      surface: isDark ? surface : Colors.white,
      error: danger,
    );
    return base.copyWith(
      colorScheme: cs,
      scaffoldBackgroundColor: isDark ? background : Colors.white,
      textTheme: base.textTheme.apply(
        bodyColor: isDark ? textPrimary : Colors.black87,
        displayColor: isDark ? textPrimary : Colors.black87,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: isDark ? textPrimary : Colors.black,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: isDark ? textPrimary : Colors.black,
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
      cardTheme: CardThemeData(
        color: isDark ? surface : Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.black12,
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? surfaceAlt : Colors.grey.shade100,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        hintStyle: TextStyle(
          color: isDark ? textSecondary : Colors.black54,
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: isDark ? surface : Colors.white,
        selectedItemColor: primary,
        unselectedItemColor: isDark ? textSecondary : Colors.black54,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
      ),
    );
  }
}
