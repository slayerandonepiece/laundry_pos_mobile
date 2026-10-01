import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/theme/text_styles.dart';

/// A compact filter dropdown: 44px tall with the same border and radius as the
/// search box. The first option is the "no filter" choice; while another is
/// selected the field is tinted so an active filter is visible at a glance.
class AppDropdownField<T> extends StatelessWidget {
  final T value;

  /// `(value, label)` pairs; the first is the unfiltered default.
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;

  const AppDropdownField({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  bool get _active => value != options.first.$1;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: _active ? AppColors.selectedSurface : AppColors.surface,
        border: Border.all(
          color: _active ? AppColors.primary : AppColors.controlBorder,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          borderRadius: BorderRadius.circular(10),
          dropdownColor: AppColors.surface,
          icon: const Icon(
            Icons.expand_more,
            size: 18,
            color: AppColors.mutedText,
          ),
          style: TextStyle(
            fontFamily: AppTextStyles.fontBody,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: _active ? AppColors.primary : AppColors.text,
          ),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
          items: [
            for (final (v, label) in options)
              DropdownMenuItem<T>(
                value: v,
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.text),
                ),
              ),
          ],
          // The field shows the same label, tinted when a filter is on.
          selectedItemBuilder: (context) => [
            for (final (_, label) in options)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
