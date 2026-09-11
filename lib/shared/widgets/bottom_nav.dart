import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/theme/text_styles.dart';

class BottomNavItem {
  final String label;
  final Widget icon;
  final Widget activeIcon;

  const BottomNavItem({
    required this.label,
    required this.icon,
    required this.activeIcon,
  });
}

/// Only used for owners now — an employee's account has a single screen
/// (Orders), so there's nothing to switch between and no bottom bar at all.
class AppBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const AppBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final effectiveBottomInset = bottomInset > 0 ? bottomInset : 26.0;

    final items = _ownerNavItems;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border, width: 1)),
      ),
      padding: EdgeInsets.only(
        top: 10,
        bottom: effectiveBottomInset,
        left: 10,
        right: 10,
      ),
      child: Row(
        children: List.generate(items.length, (index) {
          final item = items[index];
          final isSelected = index == currentIndex;
          return Expanded(
            child: InkWell(
              onTap: () => onTap(index),
              borderRadius: BorderRadius.circular(8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 52),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    isSelected ? item.activeIcon : item.icon,
                    const SizedBox(height: 6),
                    Text(
                      item.label,
                      style: isSelected
                          ? AppTextStyles.navItemActive
                          : AppTextStyles.navItem,
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  static final List<BottomNavItem> _ownerNavItems = [
    const BottomNavItem(
      label: 'Dashboard',
      icon: Icon(
        Icons.dashboard_outlined,
        size: 22,
        color: AppColors.mutedText,
      ),
      activeIcon: Icon(Icons.dashboard, size: 22, color: AppColors.primary),
    ),
    const BottomNavItem(
      label: 'Orders',
      icon: Icon(
        Icons.receipt_long_outlined,
        size: 22,
        color: AppColors.mutedText,
      ),
      activeIcon: Icon(Icons.receipt_long, size: 22, color: AppColors.primary),
    ),
    const BottomNavItem(
      label: 'More',
      icon: Icon(
        Icons.grid_view_outlined,
        size: 22,
        color: AppColors.mutedText,
      ),
      activeIcon: Icon(Icons.grid_view, size: 22, color: AppColors.primary),
    ),
  ];
}
