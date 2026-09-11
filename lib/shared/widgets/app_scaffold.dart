import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/theme/text_styles.dart';

class AppScaffold extends StatelessWidget {
  final String? title;
  final Widget? titleWidget;
  final Widget? leading;
  final List<Widget>? actions;
  final Widget body;
  final Widget? bottomNavigationBar;
  final Widget? bottomSheet;
  final bool showAppBar;
  final Color backgroundColor;

  const AppScaffold({
    super.key,
    this.title,
    this.titleWidget,
    this.leading,
    this.actions,
    required this.body,
    this.bottomNavigationBar,
    this.bottomSheet,
    this.showAppBar = true,
    this.backgroundColor = AppColors.surface,
  });

  @override
  Widget build(BuildContext context) {
    // 59px status bar inset as specified in docs/DESIGN-SPEC.md §4
    final topInset = MediaQuery.of(context).padding.top;
    final effectiveTopInset = topInset > 0 ? topInset : 59.0;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Column(
        children: [
          // Safe top inset
          SizedBox(height: effectiveTopInset),

          // 56px app bar content row + 18px bottom padding + 1px border
          if (showAppBar)
            Container(
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(
                  bottom: BorderSide(color: AppColors.border, width: 1),
                ),
              ),
              padding: const EdgeInsets.only(
                left: 20,
                right: 20,
                bottom: 18,
                top: 6,
              ),
              child: Row(
                children: [
                  if (leading != null) ...[leading!, const SizedBox(width: 12)],
                  Expanded(
                    child:
                        titleWidget ??
                        Text(
                          title ?? '',
                          style: AppTextStyles.h2,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                  ),
                  ...?actions,
                ],
              ),
            ),

          // Body content
          Expanded(child: body),
        ],
      ),
      bottomNavigationBar: bottomNavigationBar,
      bottomSheet: bottomSheet,
    );
  }
}
