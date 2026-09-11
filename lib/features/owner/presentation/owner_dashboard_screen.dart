import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:myshop/core/constants/app_colors.dart';
import 'package:myshop/core/theme/text_styles.dart';
import 'package:myshop/core/utils/currency_formatter.dart';
import 'package:myshop/features/auth/bloc/auth_bloc.dart';
import 'package:myshop/features/auth/bloc/auth_state.dart';
import 'package:myshop/features/owner/bloc/owner_bloc.dart';
import 'package:myshop/features/owner/bloc/owner_event.dart';
import 'package:myshop/features/owner/bloc/owner_state.dart';
import 'package:myshop/features/shell/presentation/store_switcher_dialog.dart';
import 'package:myshop/shared/widgets/app_card.dart';

class OwnerDashboardScreen extends StatefulWidget {
  final VoidCallback? onOrdersTabPressed;

  const OwnerDashboardScreen({super.key, this.onOrdersTabPressed});

  @override
  State<OwnerDashboardScreen> createState() => _OwnerDashboardScreenState();
}

class _OwnerDashboardScreenState extends State<OwnerDashboardScreen> {
  String _selectedPeriod = 'today'; // 'today' | '7d' | '30d'

  @override
  void initState() {
    super.initState();
    context.read<OwnerBloc>().add(LoadDashboardEvent());
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthBloc>().state;
    String storeName = 'MyShop';
    String ownerSubtitle = 'Owner';
    bool hasMultipleStores = false;
    String? paidThroughDate;

    if (authState is AuthenticatedState) {
      storeName = authState.currentStore.storeName;
      ownerSubtitle = '${authState.user.displayName} · Owner';
      hasMultipleStores = authState.availableStores.length > 1;
      paidThroughDate = authState.currentStore.paidThroughDate;
    }

    final initials = _getInitials(storeName);

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
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        storeName,
                        style: const TextStyle(
                          fontFamily: AppTextStyles.fontBody,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text,
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
          final metrics = state.metrics;

          return RefreshIndicator(
            onRefresh: () async {
              context.read<OwnerBloc>().add(LoadDashboardEvent());
            },
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // 1. Renewal warning banner (Screen A5) if due in <= 7 days
                if (paidThroughDate != null)
                  _buildRenewalBanner(paidThroughDate),

                // 2. Title and Period Dropdown
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Dashboard',
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontDisplay,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.6,
                        color: AppColors.text,
                      ),
                    ),
                    _buildPeriodSelector(),
                  ],
                ),
                const SizedBox(height: 14),

                // 3. 2x2 Metric Cards Grid
                Row(
                  children: [
                    // Card 1: Today's sales (Primary blue card)
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(15),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Today's sales",
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFFD9E7FF),
                              ),
                            ),
                            const SizedBox(height: 9),
                            Text(
                              CurrencyFormatter.format(metrics.todaySales),
                              style: const TextStyle(
                                fontFamily: AppTextStyles.fontDisplay,
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              '${metrics.todayCount} ${metrics.todayCount == 1 ? "order" : "orders"}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFFD9E7FF),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 11),

                    // Card 2: Period Sales
                    Expanded(
                      child: AppCard(
                        padding: const EdgeInsets.all(15),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _selectedPeriod == 'today'
                                  ? 'Yesterday'
                                  : (_selectedPeriod == '7d'
                                        ? 'Last 7 days'
                                        : 'This month'),
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.mutedText,
                              ),
                            ),
                            const SizedBox(height: 9),
                            Text(
                              CurrencyFormatter.format(
                                metrics.periodSales > 0
                                    ? metrics.periodSales
                                    : metrics.todaySales,
                              ),
                              style: const TextStyle(
                                fontFamily: AppTextStyles.fontDisplay,
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: AppColors.text,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              '${metrics.periodOrders > 0 ? metrics.periodOrders : metrics.todayCount} orders',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.mutedText,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 11),

                Row(
                  children: [
                    // Card 3: To collect (Uncollected balance in danger red)
                    Expanded(
                      child: InkWell(
                        onTap: widget.onOrdersTabPressed,
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.all(15),
                          decoration: BoxDecoration(
                            color: AppColors.dangerBg,
                            border: Border.all(color: AppColors.dangerBorder),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'To collect',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.danger,
                                    ),
                                  ),
                                  Icon(
                                    Icons.chevron_right,
                                    size: 16,
                                    color: AppColors.danger,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 9),
                              Text(
                                CurrencyFormatter.format(metrics.outstanding),
                                style: const TextStyle(
                                  fontFamily: AppTextStyles.fontDisplay,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.danger,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                '${metrics.todo} orders waiting',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.danger,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 11),

                    // Card 4: Orders to finish
                    Expanded(
                      child: AppCard(
                        padding: const EdgeInsets.all(15),
                        onTap: widget.onOrdersTabPressed,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'To finish',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.mutedText,
                              ),
                            ),
                            const SizedBox(height: 9),
                            Text(
                              '${metrics.todo}',
                              style: const TextStyle(
                                fontFamily: AppTextStyles.fontDisplay,
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: AppColors.text,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Row(
                              children: [
                                if (metrics.overdue > 0)
                                  Text(
                                    '${metrics.overdue} overdue · ',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.danger,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                Text(
                                  '${metrics.dueToday} due today',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.warning,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // 4. Sales by Service breakdown
                if (metrics.serviceMix.isNotEmpty) ...[
                  AppCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Sales by service',
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontBody,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.text,
                          ),
                        ),
                        const SizedBox(height: 14),
                        ...metrics.serviceMix.map((mix) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  mix.label,
                                  style: const TextStyle(
                                    fontFamily: AppTextStyles.fontBody,
                                    fontSize: 13.5,
                                    color: AppColors.text,
                                  ),
                                ),
                                Text(
                                  CurrencyFormatter.format(mix.amount),
                                  style: const TextStyle(
                                    fontFamily: AppTextStyles.fontDisplay,
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.text,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // 5. Cash Flow summary
                if (metrics.cash.isNotEmpty) ...[
                  AppCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Cash breakdown',
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontBody,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.text,
                          ),
                        ),
                        const SizedBox(height: 14),
                        ...metrics.cash.map((cp) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  cp.label,
                                  style: const TextStyle(fontSize: 13),
                                ),
                                Row(
                                  children: [
                                    Text(
                                      '+${CurrencyFormatter.format(cp.income)}',
                                      style: const TextStyle(
                                        fontFamily: AppTextStyles.fontDisplay,
                                        fontSize: 13,
                                        color: AppColors.success,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '-${CurrencyFormatter.format(cp.expenses)}',
                                      style: const TextStyle(
                                        fontFamily: AppTextStyles.fontDisplay,
                                        fontSize: 13,
                                        color: AppColors.danger,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildPeriodSelector() {
    final labels = {'today': 'Today', '7d': 'Last 7 days', '30d': 'This month'};

    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.controlBorder),
        borderRadius: BorderRadius.circular(999),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedPeriod,
          icon: const Icon(
            Icons.expand_more,
            size: 16,
            color: AppColors.mutedText,
          ),
          style: const TextStyle(
            fontFamily: AppTextStyles.fontBody,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.text,
          ),
          onChanged: (val) {
            if (val != null) {
              setState(() => _selectedPeriod = val);
              context.read<OwnerBloc>().add(LoadDashboardEvent());
            }
          },
          items: labels.entries.map((e) {
            return DropdownMenuItem<String>(value: e.key, child: Text(e.value));
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildRenewalBanner(String paidThroughDate) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.warningNoticeBg,
        border: Border.all(color: AppColors.warningBorder),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            size: 20,
            color: AppColors.warning,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Your plan renews on $paidThroughDate. Please keep payment updated.',
              style: const TextStyle(
                fontFamily: AppTextStyles.fontBody,
                fontSize: 12,
                color: AppColors.warning,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
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
