import 'package:flutter/material.dart';

/// Tema adaptativo: touchscreen = botões maiores, fontes maiores, paddings generosos.
/// Desktop = layout denso, compacto, estilo AIDA64.
class AppTheme {
  static ThemeData light({required bool isTouch}) => _base(
        brightness: Brightness.light,
        isTouch: isTouch,
        seed: const Color(0xFF0F766E),
      );

  static ThemeData dark({required bool isTouch}) => _base(
        brightness: Brightness.dark,
        isTouch: isTouch,
        seed: const Color(0xFF14B8A6),
      );

  static ThemeData _base({
    required Brightness brightness,
    required bool isTouch,
    required Color seed,
  }) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );

    final fontScale = isTouch ? 1.1 : 1.0;
    final baseFontSize = isTouch ? 17.0 : 14.0;
    final minTouchTarget = isTouch ? 56.0 : 48.0;

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      primaryColor: seed,
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
      ),
      textTheme: TextTheme(
        bodyLarge: TextStyle(fontSize: baseFontSize * fontScale),
        bodyMedium: TextStyle(fontSize: baseFontSize * 0.95 * fontScale),
        titleLarge: TextStyle(
          fontSize: baseFontSize * 1.2 * fontScale,
          fontWeight: FontWeight.w600,
        ),
        titleMedium: TextStyle(
          fontSize: baseFontSize * 1.05 * fontScale,
          fontWeight: FontWeight.w600,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          // Largura infinita aqui quebra layouts dentro de Row (tela preta).
          minimumSize: Size(0, minTouchTarget),
          padding: EdgeInsets.symmetric(horizontal: isTouch ? 24 : 16),
          textStyle: TextStyle(
            fontSize: baseFontSize * fontScale,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      cardTheme: CardThemeData(
        margin: EdgeInsets.all(isTouch ? 16 : 8),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(isTouch ? 16 : 12),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: isTouch ? 80 : 64,
      ),
    );
  }
}
