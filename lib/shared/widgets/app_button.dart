import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/theme/text_styles.dart';

class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;

  /// Shown next to the spinner while [isLoading]; without it only the spinner.
  final String? loadingLabel;
  final Widget? icon;
  final double height;
  final Color? backgroundColor;
  final EdgeInsetsGeometry? padding;

  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.loadingLabel,
    this.icon,
    this.height = 52,
    this.backgroundColor,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final bool isEnabled = onPressed != null && !isLoading;

    return SizedBox(
      height: height,
      width: double.infinity,
      child: ElevatedButton(
        onPressed: isEnabled ? onPressed : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor ?? AppColors.primary,
          disabledBackgroundColor: AppColors.disabledBg,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
          padding: padding ?? const EdgeInsets.symmetric(horizontal: 12),
        ),
        child: isLoading
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                  if (loadingLabel != null) ...[
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        loadingLabel!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.button,
                      ),
                    ),
                  ],
                ],
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[icon!, const SizedBox(width: 8)],
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        label,
                        maxLines: 1,
                        style: isEnabled
                            ? AppTextStyles.button
                            : AppTextStyles.button.copyWith(
                                color: AppColors.disabledText,
                              ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Button sizes used across the app: [main] for the full-width action of a
/// screen, [inline] for buttons in rows, dialogs and forms, [compact] inside
/// cards. Pass one as `height` instead of a literal.
class AppButtonHeight {
  static const double main = 52;
  static const double inline = 44;
  static const double compact = 36;
}

/// A borderless text action ("Clear", "Retry", "Cancel") with a tap target of
/// [height] so it lines up with neighbouring 44px fields and buttons.
class TextActionButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final double height;
  final Color? color;

  const TextActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.height = AppButtonHeight.inline,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: color ?? AppColors.primary,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          minimumSize: Size(0, height),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.buttonSecondary.copyWith(
            color: onPressed == null
                ? AppColors.disabledText
                : (color ?? AppColors.primary),
          ),
        ),
      ),
    );
  }
}

class SecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final Widget? icon;
  final double height;
  final Color? textColor;
  final Color? borderColor;
  final Color? backgroundColor;
  final EdgeInsetsGeometry? padding;

  const SecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.height = 52,
    this.textColor,
    this.borderColor,
    this.backgroundColor,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: backgroundColor ?? AppColors.surface,
          elevation: 0,
          side: BorderSide(
            color: borderColor ?? AppColors.controlBorder,
            width: 1,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
          padding: padding ?? const EdgeInsets.symmetric(horizontal: 12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[icon!, const SizedBox(width: 8)],
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: AppTextStyles.buttonSecondary.copyWith(
                    color: textColor ?? AppColors.text,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
