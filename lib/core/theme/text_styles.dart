import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

class AppTextStyles {
  AppTextStyles._();

  static const String fontDisplay = 'Manrope';
  static const String fontBody = 'DMSans';

  // Display / Headings (Manrope 800, letter-spacing -0.04em)
  static const TextStyle h1 = TextStyle(
    fontFamily: fontDisplay,
    fontSize: 26,
    fontWeight: FontWeight.w800,
    letterSpacing: -1.04, // -0.04em
    color: AppColors.text,
    height: 1.2,
  );

  static const TextStyle h2 = TextStyle(
    fontFamily: fontDisplay,
    fontSize: 20,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.8, // -0.04em
    color: AppColors.text,
    height: 1.2,
  );

  static const TextStyle h3 = TextStyle(
    fontFamily: fontDisplay,
    fontSize: 18,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.72,
    color: AppColors.text,
    height: 1.2,
  );

  // Tabular Money & Stat Figures (Manrope 800, tabular numbers)
  static const TextStyle moneyLarge = TextStyle(
    fontFamily: fontDisplay,
    fontSize: 32,
    fontWeight: FontWeight.w800,
    letterSpacing: -1.44, // -0.045em
    color: AppColors.text,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static const TextStyle moneyMedium = TextStyle(
    fontFamily: fontDisplay,
    fontSize: 20,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.9,
    color: AppColors.text,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static const TextStyle moneySmall = TextStyle(
    fontFamily: fontDisplay,
    fontSize: 14,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.63,
    color: AppColors.text,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  // Body Styles (DM Sans)
  static const TextStyle bodyLarge = TextStyle(
    fontFamily: fontBody,
    fontSize: 15,
    fontWeight: FontWeight.w500,
    color: AppColors.text,
    height: 1.45,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontFamily: fontBody,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.text,
    height: 1.45,
  );

  static const TextStyle bodySmall = TextStyle(
    fontFamily: fontBody,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: AppColors.mutedText,
    height: 1.45,
  );

  // Button text
  static const TextStyle button = TextStyle(
    fontFamily: fontBody,
    fontSize: 15,
    fontWeight: FontWeight.w700,
    color: Colors.white,
    height: 1.0,
  );

  static const TextStyle buttonSecondary = TextStyle(
    fontFamily: fontBody,
    fontSize: 15,
    fontWeight: FontWeight.w700,
    color: AppColors.text,
    height: 1.0,
  );

  // Input & Field labels
  static const TextStyle label = TextStyle(
    fontFamily: fontBody,
    fontSize: 11.5,
    fontWeight: FontWeight.w700,
    color: AppColors.mutedText,
    letterSpacing: 0.23, // 0.02em
  );

  static const TextStyle fieldLabel = label;

  static const TextStyle hint = TextStyle(
    fontFamily: fontBody,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.mutedText,
    height: 1.55,
  );

  // Pills and chips (11px minimum UI floor)
  static const TextStyle pill = TextStyle(
    fontFamily: fontBody,
    fontSize: 11,
    fontWeight: FontWeight.w700,
    height: 1.1,
  );

  static const TextStyle chip = TextStyle(
    fontFamily: fontBody,
    fontSize: 12.5,
    fontWeight: FontWeight.w600,
    color: AppColors.mutedText,
  );

  static const TextStyle chipSelected = TextStyle(
    fontFamily: fontBody,
    fontSize: 12.5,
    fontWeight: FontWeight.w600,
    color: Colors.white,
  );

  // Nav Item
  static const TextStyle navItem = TextStyle(
    fontFamily: fontBody,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: AppColors.mutedText,
  );

  static const TextStyle navItemActive = TextStyle(
    fontFamily: fontBody,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: AppColors.primary,
  );
}
