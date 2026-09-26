import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/constants/app_colors.dart';
import '../../core/theme/text_styles.dart';
import '../../features/shell/bloc/outlet_scope_cubit.dart';

/// Compact header pill showing the active outlet (or "All outlets"); tapping
/// it opens a sheet to switch. Modelled on
/// lib/features/shell/presentation/store_switcher_dialog.dart's row styling —
/// do not invent a second pattern (O5.1).
class OutletSwitcher extends StatelessWidget {
  /// Whether this screen offers owners an "All outlets" row (Dashboard,
  /// Orders and Expenses only, per O5.1). Employees never see it regardless.
  final bool showAllOutletsOption;

  const OutletSwitcher({super.key, this.showAllOutletsOption = false});

  @override
  Widget build(BuildContext context) {
    final scope = context.watch<OutletScopeCubit>().state;

    // One outlet is not a choice — hide entirely unless an owner also has
    // the All-outlets option on this screen.
    final hasChoice =
        scope.allowed.length > 1 || (scope.isOwner && showAllOutletsOption);
    if (!hasChoice) return const SizedBox.shrink();

    final label = scope.allOutlets
        ? 'All outlets'
        : scope.allowed
              .where((o) => o.id == scope.activeOutletId)
              .map((o) => o.displayName)
              .firstOrNull ??
              'Select outlet';

    return InkWell(
      onTap: () => _OutletSwitcherSheet.show(
        context,
        showAllOutletsOption: showAllOutletsOption && scope.isOwner,
      ),
      borderRadius: BorderRadius.circular(999),
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.inset,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.storefront_outlined,
              size: 16,
              color: AppColors.mutedText,
            ),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 150),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: AppTextStyles.fontBody,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
            ),
            const SizedBox(width: 2),
            const Icon(
              Icons.arrow_drop_down,
              size: 18,
              color: AppColors.mutedText,
            ),
          ],
        ),
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class _OutletSwitcherSheet extends StatelessWidget {
  final bool showAllOutletsOption;

  const _OutletSwitcherSheet({required this.showAllOutletsOption});

  static Future<void> show(
    BuildContext context, {
    required bool showAllOutletsOption,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BlocProvider.value(
        value: context.read<OutletScopeCubit>(),
        child: _OutletSwitcherSheet(showAllOutletsOption: showAllOutletsOption),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scope = context.watch<OutletScopeCubit>().state;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 10,
        bottom: MediaQuery.of(context).viewInsets.bottom + 26,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: AppColors.controlBorder,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          const Text(
            'Switch outlet',
            style: TextStyle(
              fontFamily: AppTextStyles.fontDisplay,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 14),
          if (showAllOutletsOption)
            _OutletRow(
              title: 'All outlets',
              subtitle: 'Organization-wide',
              isSelected: scope.allOutlets,
              onTap: () {
                context.read<OutletScopeCubit>().selectAllOutlets();
                Navigator.pop(context);
              },
            ),
          ...scope.allowed.map(
            (outlet) => _OutletRow(
              title: outlet.displayName,
              subtitle: outlet.outletCode,
              isSelected: !scope.allOutlets && outlet.id == scope.activeOutletId,
              isDefault: outlet.isDefault,
              onTap: () {
                context.read<OutletScopeCubit>().select(outlet.id);
                Navigator.pop(context);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _OutletRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool isSelected;
  final bool isDefault;
  final VoidCallback onTap;

  const _OutletRow({
    required this.title,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
    this.isDefault = false,
  });

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return (parts[0][0] + parts[1][0]).toUpperCase();
    }
    return name.isEmpty
        ? '?'
        : name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primaryTint : Colors.transparent,
            border: Border.all(
              color: isSelected ? const Color(0xFFCDDFFC) : Colors.transparent,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected ? AppColors.primary : AppColors.neutralBg,
                ),
                child: Center(
                  child: Text(
                    _initials(title),
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontDisplay,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: isSelected ? Colors.white : AppColors.mutedText,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontFamily: AppTextStyles.fontBody,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontFamily: AppTextStyles.fontBody,
                        fontSize: 11.5,
                        color: AppColors.mutedText,
                      ),
                    ),
                  ],
                ),
              ),
              if (isDefault)
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primaryTint,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Default',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontBody,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              if (isSelected)
                const Icon(Icons.check, size: 21, color: AppColors.primary),
            ],
          ),
        ),
      ),
    );
  }
}
