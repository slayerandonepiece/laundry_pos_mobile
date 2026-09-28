import 'package:flutter/material.dart';

/// Design tokens ported verbatim from docs/DESIGN-SPEC.md §2 and design/_head.part
class AppColors {
  AppColors._();

  // Official KlenPOS Brand Palette
  static const Color brandDeepHydro = Color(0xFF0A2540);
  static const Color brandElectricCyan = Color(0xFF00D4FF);
  static const Color brandCrispMint = Color(0xFF4CFFB3);
  static const Color brandCleanObsidian = Color(0xFF0B0F14);

  static const Color primary = Color(0xFF0758D6);
  static const Color primaryPressed = Color(0xFF064BBB);
  static const Color primaryTint = Color(0xFFEAF1FF);
  static const Color selectedSurface = Color(0xFFF5F9FF);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color inset = Color(0xFFF7F9FC);
  static const Color text = Color(0xFF102039);
  static const Color mutedText = Color(0xFF5C6878);
  static const Color faintText = Color(0xFF667388);
  static const Color border = Color(0xFFE8ECF1);
  static const Color controlBorder = Color(0xFFDCE2E9);
  static const Color divider = Color(0xFFEEF1F6);

  // Success (Paid, delivered)
  static const Color success = Color(0xFF0F6E4C);
  static const Color successBg = Color(0xFFE7F5EF);

  // Violet (Ready work status) — matches the workspace statusTone() tokens,
  // keeping amber for payment states only (O8.1).
  static const Color violet = Color(0xFF6B3FC9);
  static const Color violetBg = Color(0xFFF3EEFE);

  // Warning (unpaid, renewal due)
  static const Color warning = Color(0xFF92400E);
  static const Color warningBg = Color(0xFFFEF3C7);
  static const Color warningNoticeBg = Color(0xFFFFFDF5);
  static const Color warningBorder = Color(0xFFF3D488);

  // Danger (balance due, overdue, destructive)
  static const Color danger = Color(0xFFB42318);
  static const Color dangerBg = Color(0xFFFEF2F1);
  static const Color dangerBorder = Color(0xFFF5C6C1);
  static const Color dangerInput = Color(0xFFE8918A);
  static const Color dangerInputBg = Color(0xFFFFFAFA);

  // Neutral pill (Pending)
  static const Color neutralText = Color(0xFF5C6878);
  static const Color neutralBg = Color(0xFFEFF3F8);

  // Disabled
  static const Color disabledText = Color(0xFF5A6578);
  static const Color disabledBg = Color(0xFFDBE2EC);

  // Scrim & shadows
  static const Color scrim = Color(0xFF061B3A); // 42% opacity in dialogs
  static const Color shadow = Color(0x0D102039); // rgba(16,32,57,.05)
}
