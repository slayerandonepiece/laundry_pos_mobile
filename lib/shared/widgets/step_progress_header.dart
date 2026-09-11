import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/theme/text_styles.dart';

/// The 3-step "Customer → Services → Payment" stepper shown at the top of
/// the new-order flow. currentStep is 1-indexed; steps before it are shown
/// completed (checked), the current step is an open ring, later steps are
/// dim.
class StepProgressHeader extends StatelessWidget {
  final int currentStep;

  const StepProgressHeader({super.key, required this.currentStep});

  static const _labels = ['Customer', 'Services', 'Payment'];

  @override
  Widget build(BuildContext context) {
    final currentIndex = currentStep - 1;

    return Row(
      children: List.generate(_labels.length * 2 - 1, (index) {
        if (index.isOdd) {
          final stageBeforeIndex = index ~/ 2;
          final isCompleted = stageBeforeIndex < currentIndex;
          return Expanded(
            child: Container(
              height: 2,
              margin: const EdgeInsets.only(bottom: 20),
              color: isCompleted ? AppColors.primary : AppColors.border,
            ),
          );
        }

        final stageIndex = index ~/ 2;
        final isCompleted = stageIndex < currentIndex;
        final isCurrent = stageIndex == currentIndex;

        return Column(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isCompleted ? AppColors.primary : AppColors.surface,
                border: isCompleted
                    ? null
                    : Border.all(
                        color: isCurrent
                            ? AppColors.primary
                            : AppColors.controlBorder,
                        width: isCurrent ? 2 : 1.5,
                      ),
              ),
              child: isCompleted
                  ? const Icon(Icons.check, size: 13, color: Colors.white)
                  : Center(
                      child: Text(
                        '${stageIndex + 1}',
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontBody,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: isCurrent
                              ? AppColors.primary
                              : AppColors.mutedText,
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 5),
            Text(
              _labels[stageIndex],
              style: TextStyle(
                fontFamily: AppTextStyles.fontBody,
                fontSize: 10.5,
                fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                color: isCompleted || isCurrent
                    ? AppColors.primary
                    : AppColors.mutedText,
              ),
            ),
          ],
        );
      }),
    );
  }
}
