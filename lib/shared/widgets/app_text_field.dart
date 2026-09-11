import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants/app_colors.dart';
import '../../core/theme/text_styles.dart';

class AppTextField extends StatelessWidget {
  final String? label;
  final String? hintText;
  final String? errorText;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onEditingComplete;
  final bool obscureText;
  final TextInputType keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final bool autofocus;
  final bool enabled;
  final int maxLines;
  final FocusNode? focusNode;

  const AppTextField({
    super.key,
    this.label,
    String? hintText,
    String? hint,
    this.errorText,
    this.controller,
    this.onChanged,
    this.onEditingComplete,
    this.obscureText = false,
    this.keyboardType = TextInputType.text,
    this.inputFormatters,
    this.prefixIcon,
    this.suffixIcon,
    this.autofocus = false,
    this.enabled = true,
    this.maxLines = 1,
    this.focusNode,
  }) : hintText = hintText ?? hint;

  @override
  Widget build(BuildContext context) {
    final hasError = errorText != null && errorText!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[
          Text(label!.toUpperCase(), style: AppTextStyles.label),
          const SizedBox(height: 7),
        ],
        Container(
          constraints: const BoxConstraints(minHeight: 50),
          decoration: BoxDecoration(
            color: hasError ? AppColors.dangerInputBg : AppColors.surface,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: hasError ? AppColors.dangerInput : AppColors.controlBorder,
              width: 1,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          child: Row(
            children: [
              if (prefixIcon != null) ...[
                prefixIcon!,
                const SizedBox(width: 10),
              ],
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  onChanged: onChanged,
                  onEditingComplete: onEditingComplete,
                  obscureText: obscureText,
                  keyboardType: keyboardType,
                  inputFormatters: inputFormatters,
                  autofocus: autofocus,
                  enabled: enabled,
                  maxLines: maxLines,
                  style: AppTextStyles.bodyLarge,
                  decoration: InputDecoration(
                    hintText: hintText,
                    hintStyle: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.faintText,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              if (suffixIcon != null) ...[
                const SizedBox(width: 8),
                suffixIcon!,
              ],
            ],
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: 6),
          Text(
            errorText!,
            style: const TextStyle(
              fontFamily: AppTextStyles.fontBody,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.danger,
            ),
          ),
        ],
      ],
    );
  }
}
