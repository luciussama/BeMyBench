import 'dart:ui';

import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Permite rolagem por arrasto com mouse, trackpad e touch em todas as plataformas.
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
        PointerDeviceKind.unknown,
      };
}

/// Tema adaptativo: touchscreen = alvos maiores; desktop = denso.
class AppTheme {
  static ThemeData light({required bool isTouch}) => _base(
        brightness: Brightness.light,
        isTouch: isTouch,
        seed: AppColors.accentDeep,
      );

  static ThemeData dark({required bool isTouch}) {
    final base = _base(
      brightness: Brightness.dark,
      isTouch: isTouch,
      seed: AppColors.accent,
    );
    // Sobrescreve a paleta para o visual do dashboard.
    final scheme = base.colorScheme.copyWith(
      surface: AppColors.bg,
      onSurface: AppColors.textPrimary,
      surfaceContainerHighest: AppColors.card,
      outlineVariant: AppColors.border,
      primary: AppColors.accent,
      onPrimary: const Color(0xFF04212A),
    );

    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.bg,
      canvasColor: AppColors.bg,
      cardColor: AppColors.card,
      dividerColor: AppColors.borderSoft,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.bg,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: base.cardTheme.copyWith(
        color: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
      ),
      iconTheme: const IconThemeData(color: AppColors.textSecondary),
    );
  }

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
    final minTouchTarget = isTouch ? 56.0 : 44.0;

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      primaryColor: seed,
      textTheme: TextTheme(
        bodyLarge: TextStyle(fontSize: baseFontSize * fontScale),
        bodyMedium: TextStyle(fontSize: baseFontSize * 0.95 * fontScale),
        bodySmall: TextStyle(fontSize: baseFontSize * 0.8 * fontScale),
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
          // Nunca usar Size.fromHeight: width infinito quebra Row (tela preta).
          minimumSize: Size(0, minTouchTarget),
          padding: EdgeInsets.symmetric(horizontal: isTouch ? 24 : 18),
          textStyle: TextStyle(
            fontSize: baseFontSize * fontScale,
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: isTouch ? 80 : 64,
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.accent.withValues(alpha: 0.15),
      ),
    );
  }
}
