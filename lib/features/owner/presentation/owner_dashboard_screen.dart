import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:myshop/core/constants/app_colors.dart';
import 'package:myshop/core/theme/text_styles.dart';
import 'package:myshop/core/utils/currency_formatter.dart';
import 'package:myshop/features/auth/bloc/auth_bloc.dart';
import 'package:myshop/features/auth/bloc/auth_state.dart';
import 'package:myshop/features/orders/bloc/orders_bloc.dart';
import 'package:myshop/features/orders/bloc/orders_event.dart';
import 'package:myshop/features/orders/data/models/order_model.dart';
import 'package:myshop/features/owner/bloc/owner_bloc.dart';
import 'package:myshop/features/owner/bloc/owner_event.dart';
import 'package:myshop/features/owner/bloc/owner_state.dart';
import 'package:myshop/features/owner/data/models/dashboard_model.dart';
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
  late final ScrollController _scrollController;
  bool _isCollapsed = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
    context.read<OwnerBloc>().add(LoadDashboardEvent());
    context.read<OrdersBloc>().add(LoadOrdersEvent());
  }

  void _onScroll() {
    final collapsed = _scrollController.hasClients && _scrollController.offset > 30;
    if (collapsed != _isCollapsed) {
      setState(() => _isCollapsed = collapsed);
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthBloc>().state;
    String storeName = 'MyShop';
    bool hasMultipleStores = false;

    if (authState is AuthenticatedState) {
      storeName = authState.currentStore.storeName;
      hasMultipleStores = authState.availableStores.length > 1;
    }

    final initials = _getInitials(storeName);

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: BlocBuilder<OwnerBloc, OwnerState>(
        builder: (context, ownerState) {
          final metrics = ownerState.metrics;
          final ordersState = context.watch<OrdersBloc>().state;
          final allOrders = ordersState.allOrders;

          return RefreshIndicator(
            onRefresh: () async {
              context.read<OwnerBloc>().add(LoadDashboardEvent());
              context.read<OrdersBloc>().add(LoadOrdersEvent());
            },
            child: CustomScrollView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                // 1. Header with custom SliverAppBar
                SliverAppBar(
                  pinned: true,
                  expandedHeight: 96,
                  backgroundColor: AppColors.surface,
                  surfaceTintColor: Colors.transparent,
                  elevation: 0,
                  centerTitle: false,
                  automaticallyImplyLeading: false,
                  title: _isCollapsed
                      ? InkWell(
                          onTap: hasMultipleStores ? () => StoreSwitcherDialog.show(context) : null,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 28,
                                height: 28,
                                decoration: const BoxDecoration(
                                  color: AppColors.primaryTint,
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    initials,
                                    style: const TextStyle(
                                      fontFamily: AppTextStyles.fontDisplay,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'Dashboard',
                                style: TextStyle(
                                  fontFamily: AppTextStyles.fontDisplay,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.text,
                                ),
                              ),
                            ],
                          ),
                        )
                      : null,
                  flexibleSpace: FlexibleSpaceBar(
                    collapseMode: CollapseMode.parallax,
                    background: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            InkWell(
                              onTap: hasMultipleStores ? () => StoreSwitcherDialog.show(context) : null,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '${storeName.toUpperCase()} WORKSPACE',
                                    style: const TextStyle(
                                      fontFamily: AppTextStyles.fontBody,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.8,
                                      color: AppColors.mutedText,
                                    ),
                                  ),
                                  if (hasMultipleStores) ...[
                                    const SizedBox(width: 4),
                                    const Icon(Icons.expand_more, size: 14, color: AppColors.mutedText),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                const Text(
                                  'Dashboard',
                                  style: TextStyle(
                                    fontFamily: AppTextStyles.fontDisplay,
                                    fontSize: 24,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.text,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                                _PeriodSelectorPill(
                                  selectedPeriod: _selectedPeriod,
                                  onPeriodChanged: (val) {
                                    setState(() => _selectedPeriod = val);
                                    context.read<OwnerBloc>().add(LoadDashboardEvent());
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // 2. Two Large Money Cards
                SliverToBoxAdapter(
                  child: _buildMoneyCards(metrics),
                ),

                // 3. Compact 3-Chip Operational Row
                SliverToBoxAdapter(
                  child: _buildOperationalChips(metrics),
                ),

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

                // 5. How Orders are Moving Donut Chart
                if (allOrders.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                      child: _OrdersMovingDonutChart(allOrders: allOrders),
                    ),
                  ),

                // 6. Sales by Service Horizontal Bar Chart
                if (metrics.serviceMix.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                      child: _SalesByServiceChart(serviceMix: metrics.serviceMix),
                    ),
                  ),

                const SliverToBoxAdapter(child: SizedBox(height: 28)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildMoneyCards(DashboardMetrics metrics) {
    String periodCardTitle;
    int periodSalesAmount;
    int periodOrderCount;

    if (_selectedPeriod == '7d') {
      periodCardTitle = 'Sales this week';
      periodSalesAmount = metrics.periodSales > 0 ? metrics.periodSales : metrics.todaySales;
      periodOrderCount = metrics.periodOrders > 0 ? metrics.periodOrders : metrics.todayCount;
    } else if (_selectedPeriod == '30d') {
      periodCardTitle = 'Sales this month';
      periodSalesAmount = metrics.periodSales > 0 ? metrics.periodSales : metrics.todaySales;
      periodOrderCount = metrics.periodOrders > 0 ? metrics.periodOrders : metrics.todayCount;
    } else {
      periodCardTitle = 'Sales yesterday';
      periodSalesAmount = metrics.periodSales > 0 ? metrics.periodSales : metrics.todaySales;
      periodOrderCount = metrics.periodOrders > 0 ? metrics.periodOrders : metrics.todayCount;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Row(
        children: [
          // Card 1: Sales today (distinguished by accent border & accent color)
          Expanded(
            child: AppCard(
              border: Border.all(color: AppColors.primary, width: 1.5),
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Sales today',
                    style: TextStyle(
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
                      CurrencyFormatter.format(metrics.todaySales),
                      style: const TextStyle(
                        fontFamily: AppTextStyles.fontDisplay,
                        fontSize: 28,
                        fontWeight: FontWeight.w500,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${metrics.todayCount} ${metrics.todayCount == 1 ? "order" : "orders"}',
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
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: Row(
        children: [
          Expanded(
            child: _buildOperationChip(
              label: 'Waiting',
              count: metrics.todo,
              onTap: widget.onOrdersTabPressed,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildOperationChip(
              label: 'Completed',
              count: metrics.completed,
              onTap: widget.onOrdersTabPressed,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildOperationChip(
              label: 'Due today',
              count: metrics.dueToday,
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
    VoidCallback? onTap,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: InkWell(
        onTap: onTap,
        child: Column(
          children: [
            Text(
              '$count',
              style: const TextStyle(
                fontFamily: AppTextStyles.fontDisplay,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              ),
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

  String _getInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return (parts[0][0] + parts[1][0]).toUpperCase();
    }
    return name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase();
  }
}

class _PeriodSelectorPill extends StatelessWidget {
  final String selectedPeriod;
  final ValueChanged<String> onPeriodChanged;

  const _PeriodSelectorPill({
    required this.selectedPeriod,
    required this.onPeriodChanged,
  });

  String get _label {
    switch (selectedPeriod) {
      case '7d':
        return 'This week';
      case '30d':
        return 'This month';
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
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.controlBorder),
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
                color: AppColors.text,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down, size: 16, color: AppColors.mutedText),
          ],
        ),
      ),
    );
  }
}

class _SalesTrendChart extends StatelessWidget {
  final List<CashPoint> cash;
  final String selectedPeriod;

  const _SalesTrendChart({
    required this.cash,
    required this.selectedPeriod,
  });

  String get _caption {
    if (selectedPeriod == '7d') {
      return 'How your sales moved this week';
    } else if (selectedPeriod == '30d') {
      return 'How your sales moved this month';
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

    final xInterval = (cash.length / 4).ceil().toDouble();

    return AppCard(
      padding: const EdgeInsets.all(16),
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
                  getDrawingHorizontalLine: (value) => const FlLine(color: AppColors.divider, strokeWidth: 1),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
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
                        return Text(label, style: const TextStyle(fontSize: 10, color: AppColors.mutedText));
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
                            style: const TextStyle(fontSize: 10.5, color: AppColors.mutedText),
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
                    color: AppColors.mutedText,
                    barWidth: 2.5,
                    isStrokeCapRound: true,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, barData, index) {
                        return FlDotCirclePainter(
                          radius: 3,
                          color: AppColors.mutedText,
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
                          AppColors.mutedText.withValues(alpha: 0.12),
                          AppColors.mutedText.withValues(alpha: 0.01),
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
                        final valPaise = idx < cash.length ? cash[idx].income : 0;
                        return LineTooltipItem(
                          CurrencyFormatter.format(valPaise),
                          const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12),
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

class _OrdersMovingDonutChart extends StatelessWidget {
  final List<Order> allOrders;

  const _OrdersMovingDonutChart({required this.allOrders});

  @override
  Widget build(BuildContext context) {
    if (allOrders.isEmpty) return const SizedBox.shrink();

    int pendingCount = 0;
    int inProgressCount = 0;
    int completedCount = 0;

    for (final order in allOrders) {
      if (order.isPending) {
        pendingCount++;
      } else if (order.isInProgress || order.isReady) {
        inProgressCount++;
      } else if (order.isDelivered) {
        completedCount++;
      } else {
        pendingCount++;
      }
    }

    final total = pendingCount + inProgressCount + completedCount;
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
            radius: 12,
            showTitle: false,
          ),
        );
      }
      if (inProgressCount > 0) {
        sections.add(
          PieChartSectionData(
            value: inProgressCount.toDouble(),
            color: AppColors.primary,
            radius: 12,
            showTitle: false,
          ),
        );
      }
      if (completedCount > 0) {
        sections.add(
          PieChartSectionData(
            value: completedCount.toDouble(),
            color: AppColors.success,
            radius: 12,
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
          const Text('Where your orders stand right now', style: AppTextStyles.hint),
          const SizedBox(height: 16),
          Row(
            children: [
              SizedBox(
                width: 90,
                height: 90,
                child: PieChart(
                  PieChartData(
                    sectionsSpace: 2,
                    centerSpaceRadius: 28,
                    sections: sections,
                  ),
                ),
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
                      color: AppColors.success,
                      label: 'Completed',
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
          const SizedBox(height: 2),
          const Text('Your busiest services this period', style: AppTextStyles.hint),
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
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
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
                  final amountInRupees = (serviceMix[i].amount / 100).toDouble();
                  return BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: amountInRupees,
                        color: AppColors.mutedText,
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
