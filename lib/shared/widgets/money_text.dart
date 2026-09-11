import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/theme/text_styles.dart';
import '../../core/utils/currency_formatter.dart';

class MoneyText extends StatelessWidget {
  final num amount;
  final double fontSize;
  final Color color;
  final FontWeight fontWeight;
  final double letterSpacing;

  const MoneyText(
    this.amount, {
    super.key,
    this.fontSize = 20,
    this.color = AppColors.text,
    this.fontWeight = FontWeight.w800,
    this.letterSpacing = -0.045,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      CurrencyFormatter.format(amount),
      style: TextStyle(
        fontFamily: AppTextStyles.fontDisplay,
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        letterSpacing: letterSpacing * fontSize,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}
