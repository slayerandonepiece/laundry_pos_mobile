import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/theme/text_styles.dart';

class TappableText extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  final TextStyle? style;
  final Color? color;
  final EdgeInsetsGeometry padding;

  const TappableText({
    super.key,
    required this.text,
    required this.onTap,
    this.style,
    this.color,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        child: Padding(
          padding: padding,
          child: Text(
            text,
            style: (style ?? AppTextStyles.bodyMedium).copyWith(
              color: color ?? AppColors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
