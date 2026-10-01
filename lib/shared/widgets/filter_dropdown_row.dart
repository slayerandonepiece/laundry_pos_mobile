import 'package:flutter/material.dart';

import 'app_button.dart';

/// Two filter dropdowns with a Clear action.
///
/// From 320pt of available width up, Clear sits on the same row in a
/// permanently reserved slot so the dropdowns never change width. Narrower
/// than that, the slot would squeeze the labels, so the dropdowns take the
/// full row and Clear moves to its own right-aligned line, shown only when
/// [showClear] is true. Builders receive `compact` so callers can shorten
/// their labels.
class FilterDropdownRow extends StatelessWidget {
  static const double compactBelow = 320;

  final Widget Function(bool compact) first;
  final Widget Function(bool compact) second;
  final bool showClear;
  final VoidCallback onClear;

  const FilterDropdownRow({
    super.key,
    required this.first,
    required this.second,
    required this.showClear,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < compactBelow;
        final clear = TextActionButton(label: 'Clear', onPressed: onClear);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: first(compact)),
                const SizedBox(width: 8),
                Expanded(child: second(compact)),
                if (!compact)
                  SizedBox(width: 64, child: showClear ? clear : null),
              ],
            ),
            if (compact && showClear)
              Align(alignment: Alignment.centerRight, child: clear),
          ],
        );
      },
    );
  }
}
