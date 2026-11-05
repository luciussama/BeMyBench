import 'package:flutter/material.dart';

/// Paleta do BMyBench — tema escuro "dashboard técnico".
class AppColors {
  static const bg = Color(0xFF0B1016);
  static const surface = Color(0xFF0F1620);
  static const card = Color(0xFF111A23);
  static const cardAlt = Color(0xFF0D141C);
  static const border = Color(0xFF1E2A36);
  static const borderSoft = Color(0xFF18222D);

  static const textPrimary = Color(0xFFE6EDF3);
  static const textSecondary = Color(0xFF9FB0C0);
  static const textMuted = Color(0xFF6B7C8C);

  static const accent = Color(0xFF22D3EE);
  static const accentDeep = Color(0xFF0E7490);
  static const green = Color(0xFF34D399);
  static const orange = Color(0xFFF59E0B);
  static const red = Color(0xFFF87171);
  static const violet = Color(0xFF818CF8);

  static Color loadColor(double pct) {
    if (pct < 50) return accent;
    if (pct < 80) return orange;
    return red;
  }
}
