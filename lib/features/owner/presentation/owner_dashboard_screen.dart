import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:myshop/core/constants/app_colors.dart';
import 'package:myshop/core/theme/text_styles.dart';
import 'package:myshop/core/utils/currency_formatter.dart';
import 'package:myshop/core/utils/date_formatter.dart';
import 'package:myshop/core/sync/sync_engine.dart';
import 'package:myshop/core/sync/sync_manager.dart';
import 'package:myshop/features/auth/bloc/auth_bloc.dart';
import 'package:myshop/features/auth/bloc/auth_state.dart';
import 'package:myshop/features/orders/bloc/orders_bloc.dart';
import 'package:myshop/features/orders/bloc/orders_event.dart';
import 'package:myshop/features/orders/data/models/order_model.dart';
import 'package:myshop/features/owner/bloc/owner_bloc.dart';
import 'package:myshop/features/owner/bloc/owner_event.dart';
import 'package:myshop/features/owner/bloc/owner_state.dart';
import 'package:myshop/features/owner/data/models/dashboard_model.dart';
import 'package:myshop/features/shell/bloc/outlet_scope_cubit.dart';
import 'package:myshop/features/shell/presentation/store_switcher_dialog.dart';
import 'package:myshop/shared/widgets/app_card.dart';
import 'package:myshop/shared/widgets/outlet_title_switcher.dart';
import 'package:myshop/shared/widgets/sync_status_bar.dart';

class OwnerDashboardScreen extends StatefulWidget {
  final VoidCallback? onOrdersTabPressed;
  final ValueNotifier<int>? resetSignal;

  const OwnerDashboardScreen({
    super.key,
    this.onOrdersTabPressed,
    this.resetSignal,
  });

  @override
  State<OwnerDashboardScreen> createState() => _OwnerDashboardScreenState();
}

class _OwnerDashboardScreenState extends State<OwnerDashboardScreen> {
  String _selectedPeriod =
      '30d'; // 'today' | '7d' | '30d' | 'quarter' | 'custom'
  DateTime? _customFrom;
  DateTime? _customTo;

  @override
  void initState() {
    super.initState();
    widget.resetSignal?.addListener(_onTabLeft);
    context.read<OwnerBloc>().add(LoadDashboardEvent());
    context.read<OrdersBloc>().add(LoadOrdersEvent());
  }

  @override
  void dispose() {
    widget.resetSignal?.removeListener(_onTabLeft);
    super.dispose();
  }

  void _onTabLeft() {
    if (_selectedPeriod != '30d' || _customFrom != null || _customTo != null) {
      setState(() {
        _selectedPeriod = '30d';
        _customFrom = null;
        _customTo = null;
      });
      context.read<OwnerBloc>().add(LoadDashboardEvent());
    }
  }

  LoadDashboardEvent _currentLoadDashboardEvent() {
    if (_customFrom != null && _customTo != null) {
      return LoadDashboardEvent(
        from: DateFormatter.toIsoDateString(_customFrom!),
        to: DateFormatter.toIsoDateString(_customTo!),
      );
    }
    return LoadDashboardEvent();
  }

  Future<void> _pickCustomDate({required bool isFrom}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom
          ? (_customFrom ?? now)
          : (_customTo ?? _customFrom ?? now),
      firstDate: DateTime(2020),
      lastDate: now,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppColors.primary,
            onPrimary: Colors.white,
            onSurface: AppColors.text,
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _customFrom = picked;
        if (_customTo != null && _customTo!.isBefore(_customFrom!)) {
          _customTo = _customFrom;
        }
      } else {
        _customTo = picked;
        if (_customFrom != null && _customFrom!.isAfter(_customTo!)) {
          _customFrom = _customTo;
        }
      }
    });
    if (!mounted) return;
    if (_customFrom != null && _customTo != null) {
      context.read<OwnerBloc>().add(_currentLoadDashboardEvent());
    }
  }

  Widget _buildCustomDateSelector() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.selectedSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: () => _pickCustomDate(isFrom: true),
                child: Row(
                  children: [
                    const Icon(
                      Icons.calendar_today_outlined,
                      size: 14,
                      color: AppColors.mutedText,
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'FROM',
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontBody,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                            color: AppColors.mutedText,
                          ),
                        ),
                        Text(
                          _customFrom != null
                              ? DateFormatter.formatShort(_customFrom!)
                              : 'Pick date',
                          style: const TextStyle(
                            fontFamily: AppTextStyles.fontBody,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.text,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Container(width: 1, height: 26, color: AppColors.border),
            const SizedBox(width: 14),
            Expanded(
              child: InkWell(
                onTap: () => _pickCustomDate(isFrom: false),
                child: Row(
                  children: [
                    const Icon(
                      Icons.calendar_today_outlined,
                      size: 14,
                      color: AppColors.mutedText,
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'TO',
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontBody,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                            color: AppColors.mutedText,
                          ),
                        ),
                        Text(
                          _customTo != null
                              ? DateFormatter.formatShort(_customTo!)
                              : 'Pick date',
                          style: const TextStyle(
                            fontFamily: AppTextStyles.fontBody,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.text,
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthBloc>().state;
    final outletScopeCubit = context.watch<OutletScopeCubit?>();
    final String storeName = authState is AuthenticatedState
        ? authState.currentStore.storeName
        : '';
    final bool hasMultipleStores =
        authState is AuthenticatedState && authState.availableStores.length > 1;

    final body = BlocConsumer<OwnerBloc, OwnerState>(
      listenWhen: (prev, curr) =>
          curr.error != null &&
          curr.messageSection == OwnerSection.dashboard &&
          (ModalRoute.of(context)?.isCurrent ?? true),
      listener: (context, ownerState) {
        if (ownerState.messageSection != OwnerSection.dashboard) return;
        if (ownerState.error != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(ownerState.error!),
              backgroundColor: AppColors.danger,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      },
      builder: (context, ownerState) {
        final metrics = ownerState.metrics;
        final ordersState = context.watch<OrdersBloc>().state;
        final allOrders = ordersState.allOrders;

        return Column(
          children: [
            SyncStatusBar(
              onSyncNow: () {
                context.read<OwnerBloc>().add(
                  LoadDashboardEvent(refresh: true),
                );
                context.read<OrdersBloc>().add(LoadOrdersEvent());
              },
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  final done = Completer<void>();
                  final ordersBloc = context.read<OrdersBloc>();
                  context.read<OwnerBloc>().add(
                    LoadDashboardEvent(refresh: true, done: done),
                  );
                  ordersBloc.add(RefreshOrdersEvent());
                  await Future.wait([
                    done.future,
                    ordersBloc.stream.firstWhere((s) => !s.isLoading),
                  ]);
                },
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    // 1. Workspace label + period selector row
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Flexible(
                                  child: InkWell(
                                    onTap: hasMultipleStores
                                        ? () =>
                                              StoreSwitcherDialog.show(context)
                                        : null,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Flexible(
                                          child: Text(
                                            storeName.isNotEmpty
                                                ? '${storeName.toUpperCase()} WORKSPACE'
                                                : 'WORKSPACE',
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontFamily:
                                                  AppTextStyles.fontBody,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 0.8,
                                              color: AppColors.mutedText,
                                            ),
                                          ),
                                        ),
                                        if (hasMultipleStores) ...[
                                          const SizedBox(width: 4),
                                          const Icon(
                                            Icons.expand_more,
                                            size: 14,
                                            color: AppColors.mutedText,
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                _PeriodSelectorPill(
                                  selectedPeriod: _selectedPeriod,
                                  customFrom: _customFrom,
                                  customTo: _customTo,
                                  onPeriodChanged: (val) {
                                    setState(() {
                                      _selectedPeriod = val;
                                      if (val != 'custom') {
                                        _customFrom = null;
                                        _customTo = null;
                                      }
                                    });
                                    if (val != 'custom') {
                                      context.read<OwnerBloc>().add(
                                        LoadDashboardEvent(refresh: true),
                                      );
                                    }
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                    // 1b. Inline Custom Date Selector (if period is 'custom')
                    if (_selectedPeriod == 'custom')
                      SliverToBoxAdapter(child: _buildCustomDateSelector()),

                    // 2. Two Large Money Cards
                    SliverToBoxAdapter(child: _buildMoneyCards(metrics)),

                    // 3. Compact 3-Chip Operational Row
                    SliverToBoxAdapter(child: _buildOperationalChips(metrics)),

                    // 4. Sales by Date Trend Chart
                    if (metrics.cash.isNotEmpty)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                          child: _SalesTrendChart(
                            cash: metrics.cash,
                            selectedPeriod: _selectedPeriod,
                          ),
                        ),
                      ),

                    // 5. Money in & expenses Net Cash-Flow Chart
                    if (metrics.cash.isNotEmpty)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                          child: _CashFlowChart(cash: metrics.cash),
                        ),
                      ),

                    // 6. How Orders are Moving Donut Chart
                    if (allOrders.isNotEmpty)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                          child: _OrdersMovingDonutChart(allOrders: allOrders),
                        ),
                      ),

                    // 7. Sales by Service Horizontal Bar Chart
                    if (metrics.serviceMix.isNotEmpty)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                          child: _SalesByServiceChart(
                            serviceMix: metrics.serviceMix,
                          ),
                        ),
                      ),

                    const SliverToBoxAdapter(child: SizedBox(height: 28)),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        titleSpacing: 20,
        title: const OutletTitleSwitcher(
          screenLabel: 'Dashboard',
          showAllOutletsOption: true,
        ),
        actions: [
          ValueListenableBuilder<SyncState>(
            valueListenable: SyncManager.instance,
            builder: (context, syncState, _) {
              if (syncState.isSyncPaused || syncState.hasError) {
                return IconButton(
                  icon: const Icon(
                    Icons.sync_problem_rounded,
                    color: AppColors.danger,
                    size: 20,
                  ),
                  tooltip: 'Retry sync',
                  onPressed: () {
                    SyncEngine.instance.retryNow();
                    context.read<OwnerBloc>().add(
                      LoadDashboardEvent(refresh: true),
                    );
                    context.read<OrdersBloc>().add(RefreshOrdersEvent());
                  },
                );
              }
              return const SizedBox.shrink();
            },
          ),
          IconButton(
            icon: const Icon(
              Icons.refresh_rounded,
              color: AppColors.mutedText,
              size: 20,
            ),
            tooltip: 'Refresh',
            onPressed: () {
              context.read<OwnerBloc>().add(LoadDashboardEvent(refresh: true));
              context.read<OrdersBloc>().add(RefreshOrdersEvent());
            },
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: AppColors.border, height: 1),
        ),
      ),
      body: outletScopeCubit != null
          ? BlocListener<OutletScopeCubit, OutletScope>(
              listenWhen: (prev, curr) =>
                  prev.activeOutletId != curr.activeOutletId ||
                  prev.allOutlets != curr.allOutlets,
              listener: (context, state) {
                context.read<OwnerBloc>().add(_currentLoadDashboardEvent());
              },
              child: body,
            )
          : body,
    );
  }

  Widget _buildMoneyCards(DashboardMetrics metrics) {
    String periodCardTitle;
    int periodSalesAmount;
    int periodOrderCount;

    if (_selectedPeriod == '7d') {
      periodCardTitle = 'Sales this week';
      periodSalesAmount = metrics.periodSales > 0
          ? metrics.periodSales
          : metrics.todaySales;
      periodOrderCount = metrics.periodOrders > 0
          ? metrics.periodOrders
          : metrics.todayCount;
    } else if (_selectedPeriod == '30d') {
      periodCardTitle = 'Sales this month';
      periodSalesAmount = metrics.periodSales > 0
          ? metrics.periodSales
          : metrics.todaySales;
      periodOrderCount = metrics.periodOrders > 0
          ? metrics.periodOrders
          : metrics.todayCount;
    } else if (_selectedPeriod == 'quarter') {
      periodCardTitle = 'Sales this quarter';
      periodSalesAmount = metrics.periodSales > 0
          ? metrics.periodSales
          : metrics.todaySales;
      periodOrderCount = metrics.periodOrders > 0
          ? metrics.periodOrders
          : metrics.todayCount;
    } else if (_selectedPeriod == 'custom') {
      periodCardTitle = 'Sales selected dates';
      periodSalesAmount = metrics.periodSales > 0
          ? metrics.periodSales
          : metrics.todaySales;
      periodOrderCount = metrics.periodOrders > 0
          ? metrics.periodOrders
          : metrics.todayCount;
    } else {
      periodCardTitle = 'Sales yesterday';
      periodSalesAmount = metrics.periodSales > 0
          ? metrics.periodSales
          : metrics.todaySales;
      periodOrderCount = metrics.periodOrders > 0
          ? metrics.periodOrders
          : metrics.todayCount;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Row(
        children: [
          // Card 1: Sales today (solid primary fill, matching web's colorful hero tile)
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Sales today',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontBody,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      CurrencyFormatter.format(metrics.todaySales),
                      style: const TextStyle(
                        fontFamily: AppTextStyles.fontDisplay,
                        fontSize: 28,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${metrics.todayCount} ${metrics.todayCount == 1 ? "order" : "orders"}',
                    style: const TextStyle(
                      fontFamily: AppTextStyles.fontBody,
                      fontSize: 11.5,
                      color: Color(0xFFD9E7FF),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Card 2: Sales this period (plain card with AppColors.text)
          Expanded(
            child: AppCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    periodCardTitle,
                    style: const TextStyle(
                      fontFamily: AppTextStyles.fontBody,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.mutedText,
                    ),
                  ),
                  const SizedBox(height: 8),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      CurrencyFormatter.format(periodSalesAmount),
                      style: const TextStyle(
                        fontFamily: AppTextStyles.fontDisplay,
                        fontSize: 28,
                        fontWeight: FontWeight.w500,
                        color: AppColors.text,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$periodOrderCount ${periodOrderCount == 1 ? "order" : "orders"}',
                    style: const TextStyle(
                      fontFamily: AppTextStyles.fontBody,
                      fontSize: 11.5,
                      color: AppColors.mutedText,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOperationalChips(DashboardMetrics metrics) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Row(
        children: [
          Expanded(
            child: _buildOperationChip(
              label: 'Open orders',
              count: metrics.todo,
              indicatorColor: AppColors.warning,
              backgroundColor: AppColors.warningBg,
              onTap: widget.onOrdersTabPressed,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildOperationChip(
              label: 'Delivered',
              count: metrics.completed,
              indicatorColor: AppColors.success,
              backgroundColor: AppColors.successBg,
              onTap: widget.onOrdersTabPressed,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildOperationChip(
              label: 'Due today',
              count: metrics.dueToday,
              indicatorColor: AppColors.primary,
              backgroundColor: AppColors.primaryTint,
              onTap: widget.onOrdersTabPressed,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOperationChip({
    required String label,
    required int count,
    required Color indicatorColor,
    required Color backgroundColor,
    VoidCallback? onTap,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: InkWell(
        onTap: onTap,
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: indicatorColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  '$count',
                  style: const TextStyle(
                    fontFamily: AppTextStyles.fontDisplay,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                fontFamily: AppTextStyles.fontBody,
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                color: AppColors.mutedText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PeriodSelectorPill extends StatelessWidget {
  final String selectedPeriod;
  final DateTime? customFrom;
  final DateTime? customTo;
  final ValueChanged<String> onPeriodChanged;

  const _PeriodSelectorPill({
    required this.selectedPeriod,
    this.customFrom,
    this.customTo,
    required this.onPeriodChanged,
  });

  String get _label {
    if (selectedPeriod == 'custom') {
      if (customFrom != null && customTo != null) {
        return '${DateFormatter.formatShort(customFrom!)} – ${DateFormatter.formatShort(customTo!)}';
      }
      return 'Custom dates';
    }
    switch (selectedPeriod) {
      case '7d':
        return 'This week';
      case '30d':
        return 'This month';
      case 'quarter':
        return 'This quarter';
      case 'today':
      default:
        return 'Today';
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      initialValue: selectedPeriod,
      tooltip: 'Select period',
      onSelected: onPeriodChanged,
      itemBuilder: (context) => const [
        PopupMenuItem(value: 'today', child: Text('Today')),
        PopupMenuItem(value: '7d', child: Text('This week')),
        PopupMenuItem(value: '30d', child: Text('This month')),
        PopupMenuItem(value: 'quarter', child: Text('This quarter')),
        PopupMenuItem(value: 'custom', child: Text('Custom dates')),
      ],
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      color: AppColors.surface,
      elevation: 3,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.selectedSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _label,
              style: const TextStyle(
                fontFamily: AppTextStyles.fontBody,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.keyboard_arrow_down,
              size: 16,
              color: AppColors.primary,
            ),
          ],
        ),
      ),
    );
  }
}

String _monthAbbr(String m) {
  final lower = m.toLowerCase();
  if (lower.startsWith('jan')) return 'Jan';
  if (lower.startsWith('feb')) return 'Feb';
  if (lower.startsWith('mar')) return 'Mar';
  if (lower.startsWith('apr')) return 'Apr';
  if (lower.startsWith('may')) return 'May';
  if (lower.startsWith('jun')) return 'Jun';
  if (lower.startsWith('jul')) return 'Jul';
  if (lower.startsWith('aug')) return 'Aug';
  if (lower.startsWith('sep')) return 'Sep';
  if (lower.startsWith('oct')) return 'Oct';
  if (lower.startsWith('nov')) return 'Nov';
  if (lower.startsWith('dec')) return 'Dec';
  return m.length > 3 ? m.substring(0, 3) : m;
}

String _formatChartLabel(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '';

  // Date ranges: "1 Sept 2026–6 Sept 2026", "1 Sep 2026 - 6 Sep 2026", "01 Sept - 06 Sept"
  final rangeRegex = RegExp(
    r'^0?(\d{1,2})\s+([A-Za-z]+)(?:\s+\d{2,4})?\s*[\-–—]\s*0?(\d{1,2})\s+([A-Za-z]+)(?:\s+\d{2,4})?$',
  );
  final rangeMatch = rangeRegex.firstMatch(trimmed);
  if (rangeMatch != null) {
    final d1 = rangeMatch.group(1)!;
    final m1 = _monthAbbr(rangeMatch.group(2)!);
    final d2 = rangeMatch.group(3)!;
    final m2 = _monthAbbr(rangeMatch.group(4)!);
    if (m1.toLowerCase() == m2.toLowerCase()) {
      return '$d1–$d2 $m1';
    } else {
      return '$d1 $m1–$d2 $m2';
    }
  }

  // Short range: "1–6 Sept", "1-6 September 2026"
  final shortRangeRegex = RegExp(
    r'^0?(\d{1,2})\s*[\-–—]\s*0?(\d{1,2})\s+([A-Za-z]+)(?:\s+\d{2,4})?$',
  );
  final shortRangeMatch = shortRangeRegex.firstMatch(trimmed);
  if (shortRangeMatch != null) {
    final d1 = shortRangeMatch.group(1)!;
    final d2 = shortRangeMatch.group(2)!;
    final m = _monthAbbr(shortRangeMatch.group(3)!);
    return '$d1–$d2 $m';
  }

  // Single date with month: "1 Sept 2026", "28 September", "01 Sep"
  final singleDateRegex = RegExp(r'^0?(\d{1,2})\s+([A-Za-z]+)(?:\s+\d{2,4})?$');
  final singleDateMatch = singleDateRegex.firstMatch(trimmed);
  if (singleDateMatch != null) {
    final d = singleDateMatch.group(1)!;
    final m = _monthAbbr(singleDateMatch.group(2)!);
    return '$d $m';
  }

  // ISO date: "2026-09-01"
  final isoMatch = RegExp(r'^\d{4}-(\d{2})-(\d{2})$').firstMatch(trimmed);
  if (isoMatch != null) {
    final monthNum = int.tryParse(isoMatch.group(1)!) ?? 0;
    final dayNum = int.tryParse(isoMatch.group(2)!) ?? 0;
    const months = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    if (monthNum >= 1 && monthNum <= 12) {
      return '$dayNum ${months[monthNum]}';
    }
  }

  // Full weekday names: "Monday" -> "Mon"
  const fullDays = {
    'monday': 'Mon',
    'tuesday': 'Tue',
    'wednesday': 'Wed',
    'thursday': 'Thu',
    'friday': 'Fri',
    'saturday': 'Sat',
    'sunday': 'Sun',
  };
  if (fullDays.containsKey(trimmed.toLowerCase())) {
    return fullDays[trimmed.toLowerCase()]!;
  }

  // Month alone: "September 2026" or "September"
  final monthRegex = RegExp(r'^([A-Za-z]+)(?:\s+\d{2,4})?$');
  final monthMatch = monthRegex.firstMatch(trimmed);
  if (monthMatch != null) {
    final mStr = monthMatch.group(1)!;
    final m = _monthAbbr(mStr);
    const validMonths = [
      'jan',
      'feb',
      'mar',
      'apr',
      'may',
      'jun',
      'jul',
      'aug',
      'sep',
      'oct',
      'nov',
      'dec',
    ];
    if (validMonths.contains(m.toLowerCase())) {
      return m;
    }
  }

  if (trimmed.length <= 8) return trimmed;
  return '${trimmed.substring(0, 7)}…';
}

bool _shouldShowChartLabel(int idx, int totalCount) {
  if (totalCount <= 7) return true;
  final step = (totalCount / 4).ceil();
  if (idx == 0 || idx == totalCount - 1) return true;
  return idx % step == 0 && (totalCount - 1 - idx) >= (step / 2);
}

@visibleForTesting
String formatChartLabel(String raw) => _formatChartLabel(raw);

@visibleForTesting
bool shouldShowChartLabel(int idx, int totalCount) =>
    _shouldShowChartLabel(idx, totalCount);

class _SalesTrendChart extends StatelessWidget {
  final List<CashPoint> cash;
  final String selectedPeriod;

  const _SalesTrendChart({required this.cash, required this.selectedPeriod});

  String get _caption {
    if (selectedPeriod == '7d') {
      return 'How your sales moved this week';
    } else if (selectedPeriod == '30d') {
      return 'How your sales moved this month';
    } else if (selectedPeriod == 'quarter') {
      return 'How your sales moved this quarter';
    } else if (selectedPeriod == 'custom') {
      return 'How your sales moved in selected dates';
    }
    return 'How your sales moved today';
  }

  @override
  Widget build(BuildContext context) {
    if (cash.isEmpty) return const SizedBox.shrink();

    final spots = <FlSpot>[];
    double maxY = 0;
    for (int i = 0; i < cash.length; i++) {
      final y = (cash[i].income / 100).toDouble();
      if (y > maxY) maxY = y;
      spots.add(FlSpot(i.toDouble(), y));
    }
    if (maxY == 0) maxY = 100;

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Sales by date',
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontBody,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(_caption, style: AppTextStyles.hint),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primaryTint,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'Collected',
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontBody,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 180,
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: (cash.length - 1).toDouble().clamp(0, double.infinity),
                minY: 0,
                maxY: maxY * 1.15,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) =>
                      const FlLine(color: AppColors.divider, strokeWidth: 1),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 42,
                      getTitlesWidget: (value, meta) {
                        if (value == meta.max || value == meta.min) {
                          return const SizedBox.shrink();
                        }
                        String label;
                        if (value >= 1000) {
                          final inK = value / 1000;
                          label = inK % 1 == 0
                              ? '₹${inK.toInt()}k'
                              : '₹${inK.toStringAsFixed(1)}k';
                        } else {
                          label = '₹${value.toInt()}';
                        }
                        return Text(
                          label,
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.mutedText,
                          ),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      interval: 1,
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (value != idx.toDouble() ||
                            idx < 0 ||
                            idx >= cash.length) {
                          return const SizedBox.shrink();
                        }
                        if (!_shouldShowChartLabel(idx, cash.length)) {
                          return const SizedBox.shrink();
                        }
                        return SideTitleWidget(
                          meta: meta,
                          space: 6,
                          child: Text(
                            _formatChartLabel(cash[idx].label),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontFamily: AppTextStyles.fontBody,
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: AppColors.mutedText,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    curveSmoothness: 0.35,
                    color: AppColors.primary,
                    barWidth: 2.5,
                    isStrokeCapRound: true,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, barData, index) {
                        return FlDotCirclePainter(
                          radius: 3.5,
                          color: AppColors.primary,
                          strokeWidth: 2,
                          strokeColor: Colors.white,
                        );
                      },
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          AppColors.primary.withValues(alpha: 0.20),
                          AppColors.primary.withValues(alpha: 0.01),
                        ],
                      ),
                    ),
                  ),
                ],
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => AppColors.text,
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((spot) {
                        final idx = spot.x.toInt();
                        final valPaise = idx < cash.length
                            ? cash[idx].income
                            : 0;
                        final period = idx < cash.length
                            ? _formatChartLabel(cash[idx].label)
                            : '';
                        return LineTooltipItem(
                          '$period\nCollected: ${CurrencyFormatter.format(valPaise)}',
                          const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        );
                      }).toList();
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CashFlowChart extends StatelessWidget {
  final List<CashPoint> cash;

  const _CashFlowChart({required this.cash});

  @override
  Widget build(BuildContext context) {
    if (cash.isEmpty) return const SizedBox.shrink();

    final totalIncome = cash.fold<int>(0, (s, c) => s + c.income);
    final totalExpenses = cash.fold<int>(0, (s, c) => s + c.expenses);
    final net = totalIncome - totalExpenses;

    double maxVal = 0;
    for (final c in cash) {
      final inc = (c.income / 100).toDouble();
      final exp = (c.expenses / 100).toDouble();
      if (inc > maxVal) maxVal = inc;
      if (exp > maxVal) maxVal = exp;
    }
    if (maxVal == 0) maxVal = 100;

    final double rodWidth;
    final double barsSpace;
    if (cash.length <= 5) {
      rodWidth = 11.0;
      barsSpace = 4.0;
    } else if (cash.length <= 8) {
      rodWidth = 8.0;
      barsSpace = 3.0;
    } else {
      rodWidth = 5.0;
      barsSpace = 2.0;
    }

    final groups = <BarChartGroupData>[];
    for (int i = 0; i < cash.length; i++) {
      final inc = (cash[i].income / 100).toDouble();
      final exp = (cash[i].expenses / 100).toDouble();
      groups.add(
        BarChartGroupData(
          x: i,
          barsSpace: barsSpace,
          barRods: [
            BarChartRodData(
              toY: inc,
              color: AppColors.primary,
              width: rodWidth,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(3),
              ),
              backDrawRodData: BackgroundBarChartRodData(
                show: true,
                toY: maxVal * 1.15,
                color: AppColors.border.withValues(alpha: 0.35),
              ),
            ),
            BarChartRodData(
              toY: exp,
              color: AppColors.warning,
              width: rodWidth,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(3),
              ),
              backDrawRodData: BackgroundBarChartRodData(
                show: true,
                toY: maxVal * 1.15,
                color: AppColors.border.withValues(alpha: 0.35),
              ),
            ),
          ],
        ),
      );
    }

    final netLabel = net < 0
        ? '-${CurrencyFormatter.format(net.abs())}'
        : CurrencyFormatter.format(net);

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Collected vs expenses — this month',
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontBody,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'payments collected this month',
                      style: AppTextStyles.hint,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildLegendBadge(
                    color: AppColors.primary,
                    label: 'Collected',
                  ),
                  const SizedBox(width: 8),
                  _buildLegendBadge(
                    color: AppColors.warning,
                    label: 'Expenses',
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                netLabel,
                style: TextStyle(
                  fontFamily: AppTextStyles.fontDisplay,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: net >= 0 ? AppColors.success : AppColors.danger,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'net',
                style: TextStyle(
                  fontFamily: AppTextStyles.fontBody,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.mutedText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '${CurrencyFormatter.format(totalIncome)} received',
                style: const TextStyle(
                  fontFamily: AppTextStyles.fontBody,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.mutedText,
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Text('·', style: TextStyle(color: AppColors.mutedText)),
              ),
              Text(
                '${CurrencyFormatter.format(totalExpenses)} spent',
                style: const TextStyle(
                  fontFamily: AppTextStyles.fontBody,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.mutedText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 180,
            child: BarChart(
              BarChartData(
                minY: 0,
                maxY: maxVal * 1.15,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) =>
                      const FlLine(color: AppColors.divider, strokeWidth: 1),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 42,
                      getTitlesWidget: (value, meta) {
                        if (value == meta.max || value == meta.min) {
                          return const SizedBox.shrink();
                        }
                        String label;
                        if (value >= 1000) {
                          final inK = value / 1000;
                          label = inK % 1 == 0
                              ? '₹${inK.toInt()}k'
                              : '₹${inK.toStringAsFixed(1)}k';
                        } else {
                          label = '₹${value.toInt()}';
                        }
                        return Text(
                          label,
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.mutedText,
                          ),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      interval: 1,
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (value != idx.toDouble() ||
                            idx < 0 ||
                            idx >= cash.length) {
                          return const SizedBox.shrink();
                        }
                        if (!_shouldShowChartLabel(idx, cash.length)) {
                          return const SizedBox.shrink();
                        }
                        return SideTitleWidget(
                          meta: meta,
                          space: 6,
                          child: Text(
                            _formatChartLabel(cash[idx].label),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontFamily: AppTextStyles.fontBody,
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: AppColors.mutedText,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                barGroups: groups,
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => AppColors.text,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final isIncome = rodIndex == 0;
                      final valPaise = isIncome
                          ? cash[groupIndex].income
                          : cash[groupIndex].expenses;
                      final label = isIncome ? 'Collected' : 'Expenses';
                      final period = groupIndex < cash.length
                          ? _formatChartLabel(cash[groupIndex].label)
                          : '';
                      return BarTooltipItem(
                        '$period\n$label: ${CurrencyFormatter.format(valPaise)}',
                        const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendBadge({required Color color, required String label}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            fontFamily: AppTextStyles.fontBody,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.mutedText,
          ),
        ),
      ],
    );
  }
}

class _OrdersMovingDonutChart extends StatelessWidget {
  final List<Order> allOrders;

  const _OrdersMovingDonutChart({required this.allOrders});

  @override
  Widget build(BuildContext context) {
    if (allOrders.isEmpty) return const SizedBox.shrink();

    int pendingCount = 0;
    int inProgressCount = 0;
    int readyCount = 0;
    int completedCount = 0;

    for (final order in allOrders) {
      if (order.isPending) {
        pendingCount++;
      } else if (order.isInProgress) {
        inProgressCount++;
      } else if (order.isReady) {
        readyCount++;
      } else if (order.isDelivered) {
        completedCount++;
      } else {
        pendingCount++;
      }
    }

    final total = pendingCount + inProgressCount + readyCount + completedCount;
    final sections = <PieChartSectionData>[];

    if (total == 0) {
      sections.add(
        PieChartSectionData(
          value: 1,
          color: AppColors.border,
          radius: 12,
          showTitle: false,
        ),
      );
    } else {
      if (pendingCount > 0) {
        sections.add(
          PieChartSectionData(
            value: pendingCount.toDouble(),
            color: AppColors.neutralText,
            radius: 13,
            showTitle: false,
          ),
        );
      }
      if (inProgressCount > 0) {
        sections.add(
          PieChartSectionData(
            value: inProgressCount.toDouble(),
            color: AppColors.primary,
            radius: 13,
            showTitle: false,
          ),
        );
      }
      if (readyCount > 0) {
        sections.add(
          PieChartSectionData(
            value: readyCount.toDouble(),
            color: AppColors.violet,
            radius: 13,
            showTitle: false,
          ),
        );
      }
      if (completedCount > 0) {
        sections.add(
          PieChartSectionData(
            value: completedCount.toDouble(),
            color: AppColors.success,
            radius: 13,
            showTitle: false,
          ),
        );
      }
    }

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'How orders are moving',
            style: TextStyle(
              fontFamily: AppTextStyles.fontBody,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'Where your orders stand right now',
            style: AppTextStyles.hint,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 90,
                    height: 90,
                    child: PieChart(
                      PieChartData(
                        sectionsSpace: 2.5,
                        centerSpaceRadius: 28,
                        sections: sections,
                      ),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$total',
                        style: const TextStyle(
                          fontFamily: AppTextStyles.fontDisplay,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.text,
                          height: 1.0,
                        ),
                      ),
                      const Text(
                        'orders',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w500,
                          color: AppColors.mutedText,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  children: [
                    _buildLegendItem(
                      color: AppColors.neutralText,
                      label: 'Pending',
                      count: pendingCount,
                    ),
                    const SizedBox(height: 10),
                    _buildLegendItem(
                      color: AppColors.primary,
                      label: 'In progress',
                      count: inProgressCount,
                    ),
                    const SizedBox(height: 10),
                    _buildLegendItem(
                      color: AppColors.violet,
                      label: 'Ready',
                      count: readyCount,
                    ),
                    const SizedBox(height: 10),
                    _buildLegendItem(
                      color: AppColors.success,
                      label: 'Delivered',
                      count: completedCount,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem({
    required Color color,
    required String label,
    required int count,
  }) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontFamily: AppTextStyles.fontBody,
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AppColors.text,
          ),
        ),
        const Spacer(),
        Text(
          '$count',
          style: const TextStyle(
            fontFamily: AppTextStyles.fontDisplay,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.text,
          ),
        ),
      ],
    );
  }
}

class _SalesByServiceChart extends StatelessWidget {
  final List<ServiceMixItem> serviceMix;

  const _SalesByServiceChart({required this.serviceMix});

  static const _serviceColors = [
    AppColors.primary, // Brand blue
    Color(0xFF0F6E4C), // Success emerald
    Color(0xFF2563EB), // Vibrant blue
    Color(0xFFD97706), // Amber
    Color(0xFF7C3AED), // Purple
    Color(0xFF0284C7), // Sky blue
  ];

  @override
  Widget build(BuildContext context) {
    if (serviceMix.isEmpty) return const SizedBox.shrink();

    double maxVal = 0;
    for (final item in serviceMix) {
      final v = (item.amount / 100).toDouble();
      if (v > maxVal) maxVal = v;
    }
    if (maxVal == 0) maxVal = 100;

    return AppCard(
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
          const SizedBox(height: 2),
          const Text(
            'Your busiest services this period',
            style: AppTextStyles.hint,
          ),
          const SizedBox(height: 16),
          ...List.generate(serviceMix.length, (i) {
            final item = serviceMix[i];
            final color = _serviceColors[i % _serviceColors.length];
            final fraction = maxVal > 0
                ? (item.amount / 100).toDouble() / maxVal
                : 0.0;
            return Padding(
              padding: EdgeInsets.only(
                bottom: i == serviceMix.length - 1 ? 0 : 14,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item.label,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.text,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        CurrencyFormatter.format(item.amount),
                        style: const TextStyle(
                          fontFamily: AppTextStyles.fontDisplay,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return Stack(
                          children: [
                            Container(height: 8, color: AppColors.neutralBg),
                            Container(
                              height: 8,
                              width:
                                  constraints.maxWidth *
                                  fraction.clamp(0.03, 1.0),
                              color: color,
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
