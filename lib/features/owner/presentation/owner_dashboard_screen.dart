import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:myshop/core/constants/app_colors.dart';
import 'package:myshop/core/theme/text_styles.dart';
import 'package:myshop/core/utils/currency_formatter.dart';
import 'package:myshop/core/utils/date_formatter.dart';
import 'package:myshop/features/auth/bloc/auth_bloc.dart';
import 'package:myshop/features/auth/bloc/auth_state.dart';
import 'package:myshop/features/orders/bloc/orders_bloc.dart';
import 'package:myshop/features/orders/bloc/orders_event.dart';
import 'package:myshop/features/orders/data/models/order_model.dart';
import 'package:myshop/features/orders/presentation/order_detail_screen.dart';
import 'package:myshop/features/owner/bloc/owner_bloc.dart';
import 'package:myshop/features/owner/bloc/owner_event.dart';
import 'package:myshop/features/owner/bloc/owner_state.dart';
import 'package:myshop/features/owner/data/models/dashboard_model.dart';
import 'package:myshop/features/shell/presentation/store_switcher_dialog.dart';
import 'package:myshop/shared/widgets/app_card.dart';
import 'package:myshop/shared/widgets/empty_state.dart';
import 'package:myshop/shared/widgets/status_pill.dart';
import 'package:myshop/shared/widgets/sticky_header_delegate.dart';

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
    context.read<OrdersBloc>().add(LoadOrdersEvent());
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
        builder: (context, ownerState) {
          final metrics = ownerState.metrics;
          final ordersState = context.watch<OrdersBloc>().state;
          final allOrders = ordersState.allOrders;
          final pendingOrders = allOrders
              .where((o) => !o.isDelivered)
              .toList()
            ..sort((a, b) => a.dueDateTime.compareTo(b.dueDateTime));
          final ordersToFinish = pendingOrders.take(5).toList();

          return RefreshIndicator(
            onRefresh: () async {
              context.read<OwnerBloc>().add(LoadDashboardEvent());
              context.read<OrdersBloc>().add(LoadOrdersEvent());
            },
            child: CustomScrollView(
              slivers: [
                // 1. Renewal warning banner (Screen A5) if due in <= 7 days
                if (paidThroughDate != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                      child: _RenewalBanner(paidThroughDate: paidThroughDate),
                    ),
                  ),

                // 2. Title and Period Dropdown (pinned sticky header)
                SliverPersistentHeader(
                  pinned: true,
                  delegate: StickyHeaderDelegate(
                    height: 58,
                    child: Container(
                      color: AppColors.surface,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      child: Row(
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
                          _PeriodSelector(
                            selectedPeriod: _selectedPeriod,
                            onPeriodChanged: (val) {
                              setState(() => _selectedPeriod = val);
                              context.read<OwnerBloc>().add(LoadDashboardEvent());
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // 3. 2x2 Metric Cards Grid
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 11,
                      crossAxisSpacing: 11,
                      childAspectRatio: 1.3,
                    ),
                    delegate: SliverChildListDelegate([
                      // Card 1: Today's sales (Primary blue card)
                      _MetricCard(
                        label: "Today's sales",
                        value: CurrencyFormatter.format(metrics.todaySales),
                        subtitle:
                            '${metrics.todayCount} ${metrics.todayCount == 1 ? "order" : "orders"}',
                        variant: MetricCardVariant.primary,
                      ),

                      // Card 2: Period Sales
                      _MetricCard(
                        label: _selectedPeriod == 'today'
                            ? 'Yesterday'
                            : (_selectedPeriod == '7d'
                                ? 'Last 7 days'
                                : 'This month'),
                        value: CurrencyFormatter.format(
                          metrics.periodSales > 0
                              ? metrics.periodSales
                              : metrics.todaySales,
                        ),
                        subtitle:
                            '${metrics.periodOrders > 0 ? metrics.periodOrders : metrics.todayCount} orders',
                        variant: MetricCardVariant.standard,
                      ),

                      // Card 3: To collect (Uncollected balance in danger red)
                      _MetricCard(
                        label: 'To collect',
                        value: CurrencyFormatter.format(metrics.outstanding),
                        subtitle: '${metrics.todo} orders waiting',
                        variant: MetricCardVariant.danger,
                        onTap: widget.onOrdersTabPressed,
                      ),

                      // Card 4: Orders to finish
                      _MetricCard(
                        label: 'To finish',
                        value: '${metrics.todo}',
                        variant: MetricCardVariant.standard,
                        onTap: widget.onOrdersTabPressed,
                        subtitleWidget: Row(
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
                      ),
                    ]),
                  ),
                ),

                // 4. Sales Trend Chart
                if (metrics.cash.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                      child: _SalesTrendChart(cash: metrics.cash),
                    ),
                  ),

                // 5. Order Status Donut
                if (metrics.completed > 0 || metrics.todo > 0)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                      child: _OrderStatusDonut(
                        completed: metrics.completed,
                        todo: metrics.todo,
                      ),
                    ),
                  ),

                // 6. Sales by Service breakdown
                if (metrics.serviceMix.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                      child: _SalesByServiceChart(
                        serviceMix: metrics.serviceMix,
                      ),
                    ),
                  ),

                // 7. Cash Flow summary
                if (metrics.cash.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                      child: _CashBreakdownChart(cash: metrics.cash),
                    ),
                  ),

                // 8. Orders to finish section
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 22, 20, 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Orders to finish',
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontDisplay,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.text,
                          ),
                        ),
                        if (ordersToFinish.isNotEmpty &&
                            widget.onOrdersTabPressed != null)
                          InkWell(
                            onTap: widget.onOrdersTabPressed,
                            child: const Text(
                              'View all',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

                if (ordersToFinish.isEmpty)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(20, 8, 20, 24),
                      child: EmptyState(
                        icon: Icons.check_circle_outline,
                        title: 'Nothing here yet',
                        subtitle:
                            "Nothing due today or overdue, you're all caught up",
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    sliver: SliverList.separated(
                      itemCount: ordersToFinish.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final order = ordersToFinish[index];
                        return _DashboardOrderCard(
                          order: order,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    OrderDetailScreen(initialOrder: order),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
          );
        },
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

class _PeriodSelector extends StatelessWidget {
  final String selectedPeriod;
  final ValueChanged<String> onPeriodChanged;

  const _PeriodSelector({
    required this.selectedPeriod,
    required this.onPeriodChanged,
  });

  static const _labels = {
    'today': 'Today',
    '7d': 'Last 7 days',
    '30d': 'This month',
  };

  @override
  Widget build(BuildContext context) {
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
          value: selectedPeriod,
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
              onPeriodChanged(val);
            }
          },
          items: _labels.entries.map((e) {
            return DropdownMenuItem<String>(value: e.key, child: Text(e.value));
          }).toList(),
        ),
      ),
    );
  }
}

class _RenewalBanner extends StatelessWidget {
  final String paidThroughDate;

  const _RenewalBanner({required this.paidThroughDate});

  @override
  Widget build(BuildContext context) {
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
}

enum MetricCardVariant { primary, standard, danger }

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final String? subtitle;
  final Widget? subtitleWidget;
  final MetricCardVariant variant;
  final VoidCallback? onTap;

  const _MetricCard({
    required this.label,
    required this.value,
    this.subtitle,
    this.subtitleWidget,
    this.variant = MetricCardVariant.standard,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    switch (variant) {
      case MetricCardVariant.primary:
        return Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 12, color: Color(0xFFD9E7FF)),
              ),
              const SizedBox(height: 9),
              Text(
                value,
                style: const TextStyle(
                  fontFamily: AppTextStyles.fontDisplay,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 5),
              subtitleWidget ??
                  (subtitle != null
                      ? Text(
                          subtitle!,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFFD9E7FF),
                          ),
                        )
                      : const SizedBox.shrink()),
            ],
          ),
        );
      case MetricCardVariant.danger:
        return InkWell(
          onTap: onTap,
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.danger,
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: AppColors.danger,
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                Text(
                  value,
                  style: const TextStyle(
                    fontFamily: AppTextStyles.fontDisplay,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: AppColors.danger,
                  ),
                ),
                const SizedBox(height: 5),
                subtitleWidget ??
                    (subtitle != null
                        ? Text(
                            subtitle!,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.danger,
                            ),
                          )
                        : const SizedBox.shrink()),
              ],
            ),
          ),
        );
      case MetricCardVariant.standard:
        return AppCard(
          padding: const EdgeInsets.all(15),
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.mutedText,
                ),
              ),
              const SizedBox(height: 9),
              Text(
                value,
                style: const TextStyle(
                  fontFamily: AppTextStyles.fontDisplay,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 5),
              subtitleWidget ??
                  (subtitle != null
                      ? Text(
                          subtitle!,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.mutedText,
                          ),
                        )
                      : const SizedBox.shrink()),
            ],
          ),
        );
    }
  }
}

class _SalesTrendChart extends StatelessWidget {
  final List<CashPoint> cash;

  const _SalesTrendChart({required this.cash});

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

    final xInterval = (cash.length / 4).ceil().toDouble();

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Sales trend',
            style: TextStyle(
              fontFamily: AppTextStyles.fontBody,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
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
                  getDrawingHorizontalLine: (value) => const FlLine(
                    color: AppColors.divider,
                    strokeWidth: 1,
                  ),
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
                          label = '₹${(value / 1000).toStringAsFixed(1)}k';
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
                      reservedSize: 26,
                      interval: xInterval > 0 ? xInterval : 1,
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (idx < 0 || idx >= cash.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            cash[idx].label,
                            style: const TextStyle(
                              fontSize: 10.5,
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
                    color: AppColors.primary,
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: AppColors.primaryTint,
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
}

class _OrderStatusDonut extends StatelessWidget {
  final int completed;
  final int todo;

  const _OrderStatusDonut({required this.completed, required this.todo});

  @override
  Widget build(BuildContext context) {
    if (completed == 0 && todo == 0) return const SizedBox.shrink();

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Order status',
            style: TextStyle(
              fontFamily: AppTextStyles.fontBody,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              SizedBox(
                width: 120,
                height: 120,
                child: PieChart(
                  PieChartData(
                    sectionsSpace: 3,
                    centerSpaceRadius: 36,
                    sections: [
                      if (completed > 0)
                        PieChartSectionData(
                          value: completed.toDouble(),
                          color: AppColors.success,
                          radius: 22,
                          showTitle: false,
                        ),
                      if (todo > 0)
                        PieChartSectionData(
                          value: todo.toDouble(),
                          color: AppColors.warning,
                          radius: 22,
                          showTitle: false,
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLegendItem(
                      color: AppColors.success,
                      label: 'Completed',
                      count: completed,
                    ),
                    const SizedBox(height: 12),
                    _buildLegendItem(
                      color: AppColors.warning,
                      label: 'To finish',
                      count: todo,
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
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.text,
            ),
          ),
        ),
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

  @override
  Widget build(BuildContext context) {
    if (serviceMix.isEmpty) return const SizedBox.shrink();

    double maxVal = 0;
    for (final item in serviceMix) {
      final v = (item.amount / 100).toDouble();
      if (v > maxVal) maxVal = v;
    }
    if (maxVal == 0) maxVal = 100;

    final chartHeight = (serviceMix.length * 44.0).clamp(160.0, 300.0);

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
          const SizedBox(height: 16),
          SizedBox(
            height: chartHeight,
            child: BarChart(
              BarChartData(
                rotationQuarterTurns: 1,
                alignment: BarChartAlignment.spaceAround,
                maxY: maxVal * 1.25,
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 84,
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (idx < 0 || idx >= serviceMix.length) {
                          return const SizedBox.shrink();
                        }
                        return SideTitleWidget(
                          meta: meta,
                          child: Text(
                            serviceMix[idx].label,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.text,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: List.generate(serviceMix.length, (i) {
                  final amountInRupees =
                      (serviceMix[i].amount / 100).toDouble();
                  return BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: amountInRupees,
                        color: AppColors.primary,
                        width: 14,
                        borderRadius: BorderRadius.circular(4),
                        label: BarChartRodLabel(
                          show: true,
                          text: CurrencyFormatter.format(serviceMix[i].amount),
                          style: const TextStyle(
                            fontFamily: AppTextStyles.fontDisplay,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.text,
                          ),
                        ),
                      ),
                    ],
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CashBreakdownChart extends StatelessWidget {
  final List<CashPoint> cash;

  const _CashBreakdownChart({required this.cash});

  @override
  Widget build(BuildContext context) {
    if (cash.isEmpty) return const SizedBox.shrink();

    double maxVal = 0;
    for (final cp in cash) {
      final inc = (cp.income / 100).toDouble();
      final exp = (cp.expenses / 100).toDouble();
      if (inc > maxVal) maxVal = inc;
      if (exp > maxVal) maxVal = exp;
    }
    if (maxVal == 0) maxVal = 100;

    final xInterval = (cash.length / 4).ceil().toDouble();

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
              Row(
                children: [
                  _buildLegendDot(AppColors.success, 'Income'),
                  const SizedBox(width: 12),
                  _buildLegendDot(AppColors.danger, 'Expenses'),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 190,
            child: BarChart(
              BarChartData(
                maxY: maxVal * 1.2,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) => const FlLine(
                    color: AppColors.divider,
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
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
                          label = '₹${(value / 1000).toStringAsFixed(1)}k';
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
                      reservedSize: 26,
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        final step = xInterval > 0 ? xInterval.toInt() : 1;
                        if (idx < 0 || idx >= cash.length || idx % step != 0) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: SizedBox(
                            width: 56,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                cash[idx].label,
                                maxLines: 1,
                                softWrap: false,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.mutedText,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: List.generate(cash.length, (i) {
                  final cp = cash[i];
                  return BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: (cp.income / 100).toDouble(),
                        color: AppColors.success,
                        width: 10,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      BarChartRodData(
                        toY: (cp.expenses / 100).toDouble(),
                        color: AppColors.danger,
                        width: 10,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ],
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendDot(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppColors.mutedText),
        ),
      ],
    );
  }
}

class _DashboardOrderCard extends StatelessWidget {
  final Order order;
  final VoidCallback onTap;

  const _DashboardOrderCard({required this.order, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    Text(
                      order.orderCode,
                      style: const TextStyle(
                        fontFamily: AppTextStyles.fontDisplay,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.text,
                      ),
                    ),
                    StatusPill.fromStatus(order.status),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  order.name.isNotEmpty ? order.name : 'Walk-in Customer',
                  style: const TextStyle(
                    fontFamily: AppTextStyles.fontBody,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Due ${DateFormatter.formatShort(order.due)}',
                  style: AppTextStyles.hint,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            CurrencyFormatter.format(order.totalAmount),
            style: const TextStyle(
              fontFamily: AppTextStyles.fontDisplay,
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.text,
            ),
          ),
        ],
      ),
    );
  }
}
