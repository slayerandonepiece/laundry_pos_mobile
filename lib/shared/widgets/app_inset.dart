import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';

class AppInset extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? borderColor;
  final Color? backgroundColor;

  const AppInset({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    this.borderColor,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: backgroundColor ?? AppColors.inset,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: borderColor ?? AppColors.border, width: 1),
      ),
      padding: padding,
      child: child,
    );
  }
}
