import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/theme/text_styles.dart';

/// One outlet the owner can give an employee access to.
class AssignableOutlet {
  final String id;
  final String name;
  final String code;

  const AssignableOutlet({
    required this.id,
    required this.name,
    this.code = '',
  });
}

/// Which outlets an employee may work in, and the one they start in.
///
/// Controlled: the form holds [selected] and [defaultId] and gets every change
/// through [onChanged]. The default is always one of the selected outlets —
/// the first selected one if the current default is unchecked.
class OutletAssignmentField extends StatelessWidget {
  final List<AssignableOutlet> outlets;
  final Set<String> selected;
  final String? defaultId;
  final void Function(Set<String> selected, String? defaultId) onChanged;

  const OutletAssignmentField({
    super.key,
    required this.outlets,
    required this.selected,
    required this.defaultId,
    required this.onChanged,
  });

  /// The default to use for [next] given the [current] one.
  static String? resolveDefault(
    List<AssignableOutlet> outlets,
    Set<String> next,
    String? current,
  ) {
    if (next.isEmpty) return null;
    if (current != null && next.contains(current)) return current;
    for (final o in outlets) {
      if (next.contains(o.id)) return o.id;
    }
    return next.first;
  }

  void _toggle(String id) {
    final next = {...selected};
    if (!next.remove(id)) next.add(id);
    onChanged(next, resolveDefault(outlets, next, defaultId));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('OUTLETS', style: AppTextStyles.label),
        const SizedBox(height: 7),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.controlBorder),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Column(
            children: [
              for (var i = 0; i < outlets.length; i++) ...[
                if (i > 0) const Divider(height: 1, color: AppColors.divider),
                _row(outlets[i]),
              ],
            ],
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'They can only sign in to the checked outlets. The one marked '
          'Default opens first.',
          style: AppTextStyles.hint,
        ),
      ],
    );
  }

  Widget _row(AssignableOutlet outlet) {
    final checked = selected.contains(outlet.id);
    final isDefault = checked && defaultId == outlet.id;
    return InkWell(
      key: ValueKey('outlet-${outlet.id}'),
      onTap: () => _toggle(outlet.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          children: [
            Checkbox(
              value: checked,
              activeColor: AppColors.primary,
              onChanged: (_) => _toggle(outlet.id),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    outlet.name,
                    style: const TextStyle(
                      fontFamily: AppTextStyles.fontBody,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                  ),
                  if (outlet.code.isNotEmpty)
                    Text(outlet.code, style: AppTextStyles.hint),
                ],
              ),
            ),
            // Only worth choosing when there is more than one to choose from.
            if (checked && selected.length > 1)
              InkWell(
                key: ValueKey('default-${outlet.id}'),
                borderRadius: BorderRadius.circular(6),
                onTap: () => onChanged(selected, outlet.id),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isDefault
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        size: 18,
                        color: isDefault
                            ? AppColors.primary
                            : AppColors.mutedText,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Default',
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontBody,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isDefault
                              ? AppColors.primary
                              : AppColors.mutedText,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
