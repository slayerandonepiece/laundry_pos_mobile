import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:myshop/core/constants/app_colors.dart';
import 'package:myshop/core/theme/text_styles.dart';
import 'package:myshop/features/auth/bloc/auth_bloc.dart';
import 'package:myshop/features/auth/bloc/auth_state.dart';
import 'package:myshop/features/owner/bloc/owner_bloc.dart';
import 'package:myshop/features/owner/bloc/owner_state.dart';
import 'package:myshop/features/owner/presentation/change_password_screen.dart';
import 'package:myshop/features/owner/presentation/expenses_screen.dart';
import 'package:myshop/features/owner/presentation/owner_profile_screen.dart';
import 'package:myshop/features/owner/presentation/payment_methods_screen.dart';
import 'package:myshop/features/owner/presentation/services_screen.dart';
import 'package:myshop/features/owner/presentation/staff_screen.dart';
import 'package:myshop/features/owner/presentation/store_profile_screen.dart';
import 'package:myshop/features/owner/presentation/subscription_screen.dart';
import 'package:myshop/features/profile/presentation/dialogs/logout_dialog.dart';
import 'package:myshop/features/shell/presentation/store_switcher_dialog.dart';
import 'package:myshop/shared/widgets/app_card.dart';
import 'package:myshop/shared/widgets/section_header.dart';
import 'package:myshop/shared/widgets/status_pill.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthBloc>().state;
    String storeName = 'MyShop';
    String ownerSubtitle = 'Owner';
    bool hasMultipleStores = false;

    if (authState is AuthenticatedState) {
      storeName = authState.currentStore.storeName;
      ownerSubtitle = '${authState.user.displayName} · Owner';
      hasMultipleStores = authState.availableStores.length > 1;
    }

    final initials = _getInitials(storeName);
    final planBadge = _buildPlanStatusBadge(authState);

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        titleSpacing: 20,
        title: InkWell(
          onTap: hasMultipleStores
              ? () => StoreSwitcherDialog.show(context)
              : null,
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    initials,
                    style: const TextStyle(
                      fontFamily: AppTextStyles.fontDisplay,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            storeName,
                            style: const TextStyle(
                              fontFamily: AppTextStyles.fontBody,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.text,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (hasMultipleStores) ...[
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.expand_more,
                            size: 16,
                            color: AppColors.mutedText,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(ownerSubtitle, style: AppTextStyles.hint),
                  ],
                ),
              ),
              if (planBadge != null) ...[const SizedBox(width: 8), planBadge],
            ],
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: AppColors.border, height: 1),
        ),
      ),
      body: BlocBuilder<OwnerBloc, OwnerState>(
        builder: (context, state) {
          final unpaidExpenses = state.expenses.where((e) => !e.isPaid).length;

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // STORE SECTION
              const SectionHeader(title: 'STORE'),
              const SizedBox(height: 8),

              AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    _buildMenuItem(
                      context,
                      icon: Icons.inventory_2_outlined,
                      title: 'Services',
                      trailing: const Icon(
                        Icons.chevron_right,
                        color: AppColors.faintText,
                        size: 20,
                      ),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ServicesScreen(),
                        ),
                      ),
                    ),
                    const Divider(color: AppColors.border, height: 1),
                    _buildMenuItem(
                      context,
                      icon: Icons.receipt_long_outlined,
                      title: 'Expenses',
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (unpaidExpenses > 0) ...[
                            StatusPill(
                              label: '$unpaidExpenses unpaid',
                              variant: PillVariant.warning,
                            ),
                            const SizedBox(width: 8),
                          ],
                          const Icon(
                            Icons.chevron_right,
                            color: AppColors.faintText,
                            size: 20,
                          ),
                        ],
                      ),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ExpensesScreen(),
                        ),
                      ),
                    ),
                    const Divider(color: AppColors.border, height: 1),
                    _buildMenuItem(
                      context,
                      icon: Icons.people_outline,
                      title: 'Staff',
                      trailing: const Icon(
                        Icons.chevron_right,
                        color: AppColors.faintText,
                        size: 20,
                      ),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const StaffScreen()),
                      ),
                    ),
                    const Divider(color: AppColors.border, height: 1),
                    _buildMenuItem(
                      context,
                      icon: Icons.payments_outlined,
                      title: 'Payment methods',
                      trailing: const Icon(
                        Icons.chevron_right,
                        color: AppColors.faintText,
                        size: 20,
                      ),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const PaymentMethodsScreen(),
                        ),
                      ),
                    ),
                    const Divider(color: AppColors.border, height: 1),
                    _buildMenuItem(
                      context,
                      icon: Icons.storefront_outlined,
                      title: 'Store profile',
                      trailing: const Icon(
                        Icons.chevron_right,
                        color: AppColors.faintText,
                        size: 20,
                      ),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const StoreProfileScreen(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // ACCOUNT SECTION
              const SectionHeader(title: 'ACCOUNT'),
              const SizedBox(height: 8),

              AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    _buildMenuItem(
                      context,
                      icon: Icons.person_outline,
                      title: 'Your details',
                      trailing: const Icon(
                        Icons.chevron_right,
                        color: AppColors.faintText,
                        size: 20,
                      ),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const OwnerProfileScreen(),
                        ),
                      ),
                    ),
                    const Divider(color: AppColors.border, height: 1),
                    _buildMenuItem(
                      context,
                      icon: Icons.workspace_premium_outlined,
                      title: 'Subscription',
                      trailing: const Icon(
                        Icons.chevron_right,
                        color: AppColors.faintText,
                        size: 20,
                      ),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SubscriptionScreen(),
                        ),
                      ),
                    ),
                    const Divider(color: AppColors.border, height: 1),
                    _buildMenuItem(
                      context,
                      icon: Icons.lock_outline,
                      title: 'Change password',
                      trailing: const Icon(
                        Icons.chevron_right,
                        color: AppColors.faintText,
                        size: 20,
                      ),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ChangePasswordScreen(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Sign Out Button
              AppCard(
                padding: EdgeInsets.zero,
                child: _buildMenuItem(
                  context,
                  icon: Icons.logout,
                  iconColor: AppColors.danger,
                  title: 'Sign out',
                  titleColor: AppColors.danger,
                  onTap: () => _confirmSignOut(context),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildMenuItem(
    BuildContext context, {
    required IconData icon,
    Color? iconColor,
    required String title,
    Color? titleColor,
    Widget? trailing,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 21, color: iconColor ?? AppColors.primary),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontFamily: AppTextStyles.fontBody,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: titleColor ?? AppColors.text,
                ),
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }

  void _confirmSignOut(BuildContext context) {
    LogoutDialog.show(context);
  }

  Widget? _buildPlanStatusBadge(AuthState authState) {
    if (authState is! AuthenticatedState) return null;
    final paidThroughDate = authState.currentStore.paidThroughDate;
    if (paidThroughDate == null) return null;

    final parsedDate = DateTime.tryParse(paidThroughDate);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final isNearOrPast =
        parsedDate == null || parsedDate.difference(today).inDays <= 7;

    final Color bgColor;
    final Color textColor;
    final Color borderColor;
    final String label;

    if (isNearOrPast) {
      bgColor = AppColors.warningNoticeBg;
      textColor = AppColors.warning;
      borderColor = AppColors.warningBorder;
      label = 'Renews soon';
    } else {
      bgColor = AppColors.successBg;
      textColor = AppColors.success;
      borderColor = AppColors.success.withValues(alpha: 0.3);
      label = 'Active plan';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: AppTextStyles.fontBody,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
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
