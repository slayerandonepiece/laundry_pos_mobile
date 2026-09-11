import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:myshop/core/constants/app_colors.dart';
import 'package:myshop/core/theme/text_styles.dart';
import 'package:myshop/features/auth/bloc/auth_bloc.dart';
import 'package:myshop/features/auth/bloc/auth_event.dart';
import 'package:myshop/features/auth/bloc/auth_state.dart';

class StoreSwitcherDialog extends StatefulWidget {
  const StoreSwitcherDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BlocProvider.value(
        value: context.read<AuthBloc>(),
        child: const StoreSwitcherDialog(),
      ),
    );
  }

  @override
  State<StoreSwitcherDialog> createState() => _StoreSwitcherDialogState();
}

class _StoreSwitcherDialogState extends State<StoreSwitcherDialog> {
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthBloc>().state;
    if (authState is! AuthenticatedState) {
      return const SizedBox.shrink();
    }

    final currentStore = authState.currentStore;
    final allStores = authState.availableStores;
    final filtered = _filter.isEmpty
        ? allStores
        : allStores
              .where(
                (s) =>
                    s.storeName.toLowerCase().contains(_filter.toLowerCase()),
              )
              .toList();

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
          // Drag handle
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

          // Header
          const Text(
            'Switch store',
            style: TextStyle(
              fontFamily: AppTextStyles.fontDisplay,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'You have access to ${allStores.length} stores. Data never mixes between them.',
            style: AppTextStyles.hint,
          ),
          const SizedBox(height: 14),

          // Filter if more than 3 stores
          if (allStores.length > 3) ...[
            Container(
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.inset,
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 13),
              child: Row(
                children: [
                  const Icon(
                    Icons.search,
                    size: 18,
                    color: AppColors.mutedText,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.text,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Filter stores',
                        hintStyle: TextStyle(
                          fontSize: 14,
                          color: AppColors.faintText,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onChanged: (val) => setState(() => _filter = val),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],

          // Store items list
          ...filtered.map((store) {
            final isCurrent = store.storeId == currentStore.storeId;
            final initials = _getInitials(store.storeName);

            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: InkWell(
                onTap: () {
                  context.read<AuthBloc>().add(
                    StoreSelectedEvent(store.storeId),
                  );
                  Navigator.pop(context);
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 64),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isCurrent
                        ? AppColors.primaryTint
                        : Colors.transparent,
                    border: Border.all(
                      color: isCurrent
                          ? const Color(0xFFCDDFFC)
                          : Colors.transparent,
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
                          color: isCurrent
                              ? AppColors.primary
                              : AppColors.neutralBg,
                        ),
                        child: Center(
                          child: Text(
                            initials,
                            style: TextStyle(
                              fontFamily: AppTextStyles.fontDisplay,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: isCurrent
                                  ? Colors.white
                                  : AppColors.mutedText,
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
                              store.storeName,
                              style: const TextStyle(
                                fontFamily: AppTextStyles.fontBody,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.text,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              store.isOwner
                                  ? 'Owner workspace'
                                  : 'Staff member',
                              style: const TextStyle(
                                fontFamily: AppTextStyles.fontBody,
                                fontSize: 11.5,
                                color: AppColors.mutedText,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isCurrent)
                        const Icon(
                          Icons.check,
                          size: 21,
                          color: AppColors.primary,
                        ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  String _getInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return (parts[0][0] + parts[1][0]).toUpperCase();
    }
    return name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase();
  }
}
