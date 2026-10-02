import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:myshop/core/constants/app_colors.dart';
import 'package:myshop/core/theme/text_styles.dart';
import 'package:myshop/core/utils/currency_formatter.dart';
import 'package:myshop/core/utils/date_formatter.dart';
import 'package:myshop/core/sync/sync_engine.dart';
import 'package:myshop/core/sync/sync_freshness.dart';
import 'package:myshop/core/sync/sync_manager.dart';
import 'package:myshop/features/auth/bloc/auth_bloc.dart';
import 'package:myshop/features/auth/bloc/auth_state.dart';
import 'package:myshop/features/orders/bloc/orders_bloc.dart';
import 'package:myshop/features/orders/bloc/orders_state.dart';
import 'package:myshop/features/orders/bloc/orders_event.dart';
import 'package:myshop/features/orders/presentation/orders_drill_down.dart';
import 'package:myshop/features/orders/data/models/order_model.dart';
import 'package:myshop/features/owner/bloc/owner_bloc.dart';
import 'package:myshop/features/owner/bloc/owner_event.dart';
import 'package:myshop/features/owner/bloc/owner_state.dart';
import 'package:myshop/features/owner/data/models/dashboard_model.dart';
import 'package:myshop/features/shell/bloc/outlet_scope_cubit.dart';
import 'package:myshop/features/shell/presentation/store_switcher_dialog.dart';
import 'package:myshop/shared/widgets/app_button.dart';
import 'package:myshop/shared/widgets/app_card.dart';
import 'package:myshop/shared/widgets/outlet_title_switcher.dart';
import 'package:myshop/shared/widgets/period_filter.dart';
import 'package:myshop/features/orders/presentation/order_detail_screen.dart';
import 'package:myshop/shared/widgets/status_pill.dart';
import 'package:myshop/shared/widgets/sync_status_bar.dart';

class OwnerDashboardScreen extends StatefulWidget {
  /// Opens the Orders tab; [OrdersDrillDown] says which view, null for the
  /// plain list.
  final ValueChanged<OrdersDrillDown?>? onOpenOrders;
  final ValueNotifier<int>? resetSignal;

  const OwnerDashboardScreen({super.key, this.onOpenOrders, this.resetSignal});

  @override
  State<OwnerDashboardScreen> createState() => _OwnerDashboardScreenState();
}

class _OwnerDashboardScreenState extends State<OwnerDashboardScreen> {
  // Sales by date and Sales by service default to the current month (month-to-date);
  // each card keeps its own independent selection.
  PeriodRange _dateRange = PeriodRange.last7;
  PeriodRange _serviceRange = PeriodRange.thisMonth;

  StreamSubscription<OrdersState>? _ordersSub;
  Timer? _ordersRefreshTimer;
  int? _ordersSignature;

  @override
  void initState() {
    super.initState();
    widget.resetSignal?.addListener(_onTabLeft);
    context.read<OwnerBloc>().add(_currentLoadDashboardEvent(refresh: false));
    _loadSalesByDate();
    final ordersBloc = context.read<OrdersBloc>();
    ordersBloc.add(LoadOrdersEvent());
    _ordersSub = ordersBloc.stream.listen(_onOrdersChanged);
  }

  @override
  void dispose() {
    widget.resetSignal?.removeListener(_onTabLeft);
    _ordersSub?.cancel();
    _ordersRefreshTimer?.cancel();
    super.dispose();
  }

  /// Orders, their status and what was paid; anything that moves the figures.
  int _signatureOf(OrdersState s) => Object.hashAll([
    s.allOrders.length,
    for (final o in s.allOrders) Object.hash(o.id, o.status, o.paidAmount),
  ]);

  /// A sale (or a payment, or a status change) must show on the dashboard
  /// without a manual refresh; the dashboard figures come from the server.
  void _onOrdersChanged(OrdersState s) {
    if (s.isLoading) return;
    final signature = _signatureOf(s);
    final previous = _ordersSignature;
    _ordersSignature = signature;
    // The first loaded state is only the baseline (opening the screen already
    // loads the dashboard); changes after it are what need a reload.
    if (previous == null || previous == signature) return;
    _ordersRefreshTimer?.cancel();
    _ordersRefreshTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) _refreshDashboard();
    });
  }

  void _onTabLeft() => _resetCards();

  /// Sales by date opens on this week; it needs its own request because the
  /// page's own data is the whole month.
  void _loadSalesByDate() {
    context.read<OwnerBloc>().add(
      LoadCardMetricsEvent(
        card: DashboardCard.salesByDate,
        range: _dateRange,
        requestKey: _cardKey(_dateRange),
      ),
    );
  }

  /// Both cards back to their default period: this week for Sales by date,
  /// the page's own data (this month) for Sales by service.
  void _resetCards() {
    if (_dateRange.key == PeriodRange.last7.key && _serviceRange.isDefault) {
      return;
    }
    setState(() {
      _dateRange = PeriodRange.last7;
      _serviceRange = PeriodRange.thisMonth;
    });
    final bloc = context.read<OwnerBloc>();
    bloc.add(ResetCardEvent({DashboardCard.salesByService}));
    _loadSalesByDate();
  }

  String get _scopeKey {
    final scope = context.read<OutletScopeCubit?>()?.state;
    return scope == null
        ? 'none'
        : (scope.allOutlets ? 'all' : (scope.activeOutletId ?? 'none'));
  }

  /// Identifies the page's selection (its outlet scope). Sent with every load
  /// and echoed back in `OwnerState.dashboardKey`, so the screen can tell when
  /// the metrics it holds belong to a different outlet.
  String _currentRequestKey() => 'mtd|$_scopeKey';

  /// A card's selection: its range plus the outlet it is asked for.
  String _cardKey(PeriodRange r) => '${r.requestKey}|$_scopeKey';

  void _onCardRange(DashboardCard card, PeriodRange r) {
    setState(() {
      if (card == DashboardCard.salesByDate) {
        _dateRange = r;
      } else {
        _serviceRange = r;
      }
    });
    final bloc = context.read<OwnerBloc>();
    if (r.isDefault) {
      bloc.add(ResetCardEvent({card}));
    } else {
      bloc.add(
        LoadCardMetricsEvent(card: card, range: r, requestKey: _cardKey(r)),
      );
    }
  }

  /// What a card should draw for [range]: the page's data at the default
  /// period, otherwise the card's own reply — loading until it arrives.
  _CardData _cardData(
    OwnerState s,
    DashboardCard card,
    PeriodRange range,
    bool pageStale,
  ) {
    if (range.isDefault) {
      return _CardData(s.metrics, loading: pageStale);
    }
    final slice = s.cards[card];
    if (slice == null || slice.key != _cardKey(range)) {
      return const _CardData(null, loading: true);
    }
    return _CardData(
      slice.metrics,
      loading: slice.loading,
      failed: slice.failed,
    );
  }

  /// The one place that turns the page's selection into a dashboard request,
  /// used by the outlet switch, pull-to-refresh, "Sync now" and the app-bar
  /// buttons.
  LoadDashboardEvent _currentLoadDashboardEvent({
    bool refresh = true,
    Completer<void>? done,
  }) {
    // Current month (month-to-date) in daily buckets — the only request whose
    // response is cached as the default dashboard.
    final now = DateTime.now();
    return LoadDashboardEvent(
      from: DateFormatter.toIsoDateString(DateTime(now.year, now.month, 1)),
      to: DateFormatter.toIsoDateString(now),
      granularity: 'day',
      refresh: refresh,
      done: done,
      isDefaultPeriod: true,
      requestKey: _currentRequestKey(),
    );
  }

  /// Reloads the page metrics and, for a card on a non-default period, that
  /// card's own slice too — otherwise it would keep showing stale data.
  void _refreshDashboard({Completer<void>? done}) {
    final bloc = context.read<OwnerBloc>();
    bloc.add(_currentLoadDashboardEvent(done: done));
    for (final (card, range) in [
      (DashboardCard.salesByDate, _dateRange),
      (DashboardCard.salesByService, _serviceRange),
    ]) {
      if (!range.isDefault) {
        bloc.add(
          LoadCardMetricsEvent(
            card: card,
            range: range,
            requestKey: _cardKey(range),
          ),
        );
      }
    }
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
        // The metrics held belong to a different outlet than the one
        // selected (its response hasn't arrived yet): dim them instead of
        // presenting them under the new one.
        final metricsStale =
            ownerState.dashboardKey != null &&
            ownerState.dashboardKey != _currentRequestKey();
        final dateCard = _cardData(
          ownerState,
          DashboardCard.salesByDate,
          _dateRange,
          metricsStale,
        );
        final serviceCard = _cardData(
          ownerState,
          DashboardCard.salesByService,
          _serviceRange,
          metricsStale,
        );
        final ordersState = context.watch<OrdersBloc>().state;
        final allOrders = ordersState.allOrders;

        return Column(
          children: [
            SyncStatusBar(
              onSyncNow: () {
                _refreshDashboard();
                context.read<OrdersBloc>().add(LoadOrdersEvent());
              },
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  final done = Completer<void>();
                  final ordersBloc = context.read<OrdersBloc>();
                  _refreshDashboard(done: done);
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
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                    SliverOpacity(
                      opacity: metricsStale ? 0.4 : 1.0,
                      sliver: SliverMainAxisGroup(
                        slivers: [
                          // 2. Two Large Money Cards
                          SliverToBoxAdapter(child: _buildMoneyCards(metrics)),

                          // 3. Compact 3-Chip Operational Row
                          SliverToBoxAdapter(
                            child: _buildOperationalChips(metrics),
                          ),

                          // 4. Sales by Date Trend Chart — its own period filter
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                              child: _SalesTrendChart(
                                bars: dateCard.metrics?.bars ?? const [],
                                cash: dateCard.metrics?.cash ?? const [],
                                range: _dateRange,
                                loading: dateCard.loading,
                                failed: dateCard.failed,
                                onRange: (r) =>
                                    _onCardRange(DashboardCard.salesByDate, r),
                                onRetry: () => _onCardRange(
                                  DashboardCard.salesByDate,
                                  _dateRange,
                                ),
                              ),
                            ),
                          ),

                          // 5. Money in & expenses Net Cash-Flow Chart (fixed
                          // at the current month)
                          if (metrics.cashRange.isNotEmpty ||
                              metrics.cash.isNotEmpty)
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  14,
                                  20,
                                  0,
                                ),
                                // An older backend only has the calendar-month
                                // series, and says so.
                                child: metricsStale
                                    ? const _StaleChartPlaceholder()
                                    : _CashFlowChart(
                                        cash: metrics.cashRange.isNotEmpty
                                            ? metrics.cashRange
                                            : metrics.cash,
                                        periodLabel: 'This month',
                                      ),
                              ),
                            ),

                          // 6. How Orders are Moving Donut Chart
                          if (allOrders.isNotEmpty)
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  14,
                                  20,
                                  0,
                                ),
                                child: _OrdersMovingDonutChart(
                                  allOrders: allOrders,
                                ),
                              ),
                            ),

                          // 7. Sales by Service — its own period filter
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                              child: _SalesByServiceChart(
                                serviceMix:
                                    serviceCard.metrics?.serviceMix ?? const [],
                                range: _serviceRange,
                                loading: serviceCard.loading,
                                failed: serviceCard.failed,
                                onRange: (r) => _onCardRange(
                                  DashboardCard.salesByService,
                                  r,
                                ),
                                onRetry: () => _onCardRange(
                                  DashboardCard.salesByService,
                                  _serviceRange,
                                ),
                              ),
                            ),
                          ),

                          // 8. Recent orders — newest first, from the phone
                          if (allOrders.isNotEmpty)
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  14,
                                  20,
                                  0,
                                ),
                                child: _RecentOrdersCard(
                                  orders: allOrders,
                                  scope: outletScopeCubit?.state,
                                  onViewAll: _openOrders(null),
                                ),
                              ),
                            ),
                        ],
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
                    _refreshDashboard();
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
              _refreshDashboard();
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
                // Straight after a sync (sign-in) every scope is already
                // cached and current: show it, don't ask again. Any
                // non-default period isn't cached and still fetches.
                _resetCards();
                context.read<OwnerBloc>().add(
                  _currentLoadDashboardEvent(refresh: !SyncFreshness.isFresh),
                );
              },
              child: body,
            )
          : body,
    );
  }

  static String _formatKpi(int amountInPaise) {
    final rupees = amountInPaise / 100.0;
    if (rupees >= 100000) {
      final inLakhs = rupees / 100000.0;
      final formatted = inLakhs.toStringAsFixed(1);
      final trimmed = formatted.endsWith('.0')
          ? formatted.substring(0, formatted.length - 2)
          : formatted;
      return '₹${trimmed}L';
    }
    return CurrencyFormatter.format(amountInPaise);
  }

  // The default dashboard request is month-to-date, so the headline pair is
  // "Sales today" and "Sales this month", both straight from the server reply.
  Widget _buildMoneyCards(DashboardMetrics metrics) {
    const periodCardTitle = 'Sales this month';
    final int periodSalesAmount = metrics.hasPeriodSales
        ? metrics.periodSales
        : metrics.todaySales;
    final int periodOrderCount = metrics.hasPeriodSales
        ? metrics.periodOrders
        : metrics.todayCount;

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
                  Text(
                    _formatKpi(metrics.todaySales),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: AppTextStyles.fontDisplay,
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
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
                  Text(
                    _formatKpi(periodSalesAmount),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: AppTextStyles.fontDisplay,
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
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

  VoidCallback? _openOrders(OrdersDrillDown? filter) {
    final open = widget.onOpenOrders;
    return open == null ? null : () => open(filter);
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
              onTap: _openOrders(OrdersDrillDown.open),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildOperationChip(
              label: 'Delivered',
              count: metrics.completed,
              indicatorColor: AppColors.success,
              backgroundColor: AppColors.successBg,
              onTap: _openOrders(OrdersDrillDown.deliveredToday),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildOperationChip(
              label: 'Due today',
              count: metrics.dueToday,
              indicatorColor: AppColors.primary,
              backgroundColor: AppColors.primaryTint,
              onTap: _openOrders(OrdersDrillDown.dueToday),
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
    // Material under the InkWell so the splash shows over the tint.
    return Semantics(
      button: onTap != null,
      label: '$label, $count',
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
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
  if (trimmed.contains('\n')) return trimmed;

  // Month-first date ranges: "Aug 30 - Sep 05", "Aug 30 - Sep 5"
  final monthFirstRangeRegex = RegExp(
    r'^([A-Za-z]+)\s+0?(\d{1,2})(?:\s+\d{2,4})?\s*[\-–—]\s*([A-Za-z]+)\s+0?(\d{1,2})(?:\s+\d{2,4})?$',
  );
  final mfMatch = monthFirstRangeRegex.firstMatch(trimmed);
  if (mfMatch != null) {
    final m1 = _monthAbbr(mfMatch.group(1)!);
    final d1 = mfMatch.group(2)!.padLeft(2, '0');
    final m2 = _monthAbbr(mfMatch.group(3)!);
    final d2 = mfMatch.group(4)!.padLeft(2, '0');
    return '$m1 $d1 -\n$m2 $d2';
  }

  // Date ranges: "1 Sept 2026–6 Sept 2026", "1 Sep 2026 - 6 Sep 2026", "01 Sept - 06 Sept", "1 Sep–3 Sep"
  final rangeRegex = RegExp(
    r'^0?(\d{1,2})\s+([A-Za-z]+)(?:\s+(\d{2,4}))?\s*[\-–—]\s*0?(\d{1,2})\s+([A-Za-z]+)(?:\s+(\d{2,4}))?$',
  );
  final rangeMatch = rangeRegex.firstMatch(trimmed);
  if (rangeMatch != null) {
    final d1 = rangeMatch.group(1)!;
    final m1 = _monthAbbr(rangeMatch.group(2)!);
    final y1 = rangeMatch.group(3);
    final d2 = rangeMatch.group(4)!;
    final m2 = _monthAbbr(rangeMatch.group(5)!);
    final y2 = rangeMatch.group(6);
    final hasYear = y1 != null || y2 != null;
    if (hasYear) {
      if (m1.toLowerCase() == m2.toLowerCase()) {
        return '$d1–$d2\n$m1';
      } else {
        return '$d1 $m1 -\n$d2 $m2';
      }
    } else {
      final p1 = d1.padLeft(2, '0');
      final p2 = d2.padLeft(2, '0');
      return '$p1 $m1 -\n$p2 $m2';
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
    return '$d1–$d2\n$m';
  }

  // Single date with month: "1 Sept 2026", "28 September", "01 Sep", "22 Sep"
  final singleDateRegex = RegExp(r'^0?(\d{1,2})\s+([A-Za-z]+)(?:\s+\d{2,4})?$');
  final singleDateMatch = singleDateRegex.firstMatch(trimmed);
  if (singleDateMatch != null) {
    final d = singleDateMatch.group(1)!;
    final m = _monthAbbr(singleDateMatch.group(2)!);
    return '$d\n$m';
  }

  // ISO date: "2026-09-01" or "2026-09-22"
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
      return '$dayNum\n${months[monthNum]}';
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

/// What one period-filtered card draws: its metrics, or why it has none yet.
class _CardData {
  final DashboardMetrics? metrics;
  final bool loading;
  final bool failed;

  const _CardData(this.metrics, {this.loading = false, this.failed = false});
}

/// The in-card stand-in for a loading, failed or empty period, so the filter
/// above it stays usable.
class _CardStateBox extends StatelessWidget {
  final bool loading;
  final bool failed;
  final String emptyText;
  final VoidCallback onRetry;

  const _CardStateBox({
    required this.loading,
    required this.failed,
    required this.emptyText,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 150,
      width: double.infinity,
      child: Center(
        child: loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              )
            : failed
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Could not load this period',
                    style: AppTextStyles.hint,
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: 120,
                    child: SecondaryButton(
                      label: 'Retry',
                      height: AppButtonHeight.inline,
                      onPressed: onRetry,
                    ),
                  ),
                ],
              )
            : Text(emptyText, style: AppTextStyles.hint),
      ),
    );
  }
}

class _SalesTrendChart extends StatelessWidget {
  final List<DashboardBar> bars;
  final List<CashPoint> cash;
  final PeriodRange range;
  final bool loading;
  final bool failed;
  final ValueChanged<PeriodRange> onRange;
  final VoidCallback onRetry;

  const _SalesTrendChart({
    this.bars = const [],
    this.cash = const [],
    required this.range,
    required this.loading,
    required this.failed,
    required this.onRange,
    required this.onRetry,
  });

  String get _caption => switch (range.key) {
    '7d' => 'How your sales moved this week',
    '90d' => 'How your sales moved this quarter',
    'custom' => 'How your sales moved in selected dates',
    _ => 'How your sales moved this month',
  };

  @override
  Widget build(BuildContext context) {
    final useBars = bars.isNotEmpty;
    final int dataCount = useBars ? bars.length : cash.length;
    final showState = loading || failed || dataCount == 0;

    // A single day with sales would be one lonely dot: start the line at
    // zero so it reads as "from nothing to this much".
    final lead = dataCount == 1 ? 1 : 0;
    final pointCount = dataCount + lead;

    final spots = <FlSpot>[if (lead == 1) const FlSpot(0, 0)];
    double maxY = 0;
    for (int i = 0; i < dataCount; i++) {
      final amount = useBars ? bars[i].amount : cash[i].income;
      final y = (amount / 100).toDouble();
      if (y > maxY) maxY = y;
      spots.add(FlSpot((i + lead).toDouble(), y));
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
                    Text(
                      'Collected',
                      style: const TextStyle(
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
          const SizedBox(height: 12),
          PeriodFilter(
            key: const ValueKey('filter-salesByDate'),
            value: range,
            onChanged: onRange,
          ),
          const SizedBox(height: 16),
          if (showState)
            _CardStateBox(
              loading: loading,
              failed: failed,
              emptyText: 'No sales in this period',
              onRetry: onRetry,
            )
          else
            Builder(
              builder: (context) {
                final screenHeight = MediaQuery.of(context).size.height;
                final chartHeight = (screenHeight * 0.28).clamp(170.0, 240.0);
                final yInterval = (maxY * 1.15) / 3;

                final grid = FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: yInterval > 0 ? yInterval : 25,
                  getDrawingHorizontalLine: (value) =>
                      const FlLine(color: AppColors.divider, strokeWidth: 1),
                );
                final titles = FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 44,
                      interval: yInterval > 0 ? yInterval : 25,
                      getTitlesWidget: (value, meta) {
                        String label;
                        if (value.round() == 0) {
                          label = '₹0';
                        } else if (value >= 1000) {
                          final inK = value / 1000;
                          label = inK % 1 == 0
                              ? '₹${inK.toInt()}k'
                              : '₹${inK.toStringAsFixed(1)}k';
                        } else {
                          label = '₹${value.toInt()}';
                        }
                        return SideTitleWidget(
                          meta: meta,
                          fitInside: SideTitleFitInsideData.fromTitleMeta(meta),
                          child: Text(
                            label,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.mutedText,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 38,
                      interval: 1,
                      getTitlesWidget: (value, meta) {
                        final raw = value.toInt();
                        final idx = raw - lead;
                        if (value != raw.toDouble() ||
                            idx < 0 ||
                            idx >= dataCount) {
                          return const SizedBox.shrink();
                        }
                        if (!_shouldShowChartLabel(idx, dataCount)) {
                          return const SizedBox.shrink();
                        }
                        final rawLabel = useBars
                            ? bars[idx].label
                            : cash[idx].label;
                        return SideTitleWidget(
                          meta: meta,
                          space: 6,
                          child: Text(
                            _formatChartLabel(rawLabel),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontFamily: AppTextStyles.fontBody,
                              fontSize: 11,
                              height: 1.15,
                              fontWeight: FontWeight.w500,
                              color: AppColors.mutedText,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                );

                return SizedBox(
                  height: chartHeight,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 12, left: 4, top: 8),
                    child: LineChart(
                      duration: Duration.zero,
                      LineChartData(
                        minX: 0,
                        // A single point (one-day custom range) would make
                        // minX == maxX, which fl_chart can't scale.
                        maxX: pointCount > 1 ? (pointCount - 1).toDouble() : 1,
                        minY: 0,
                        maxY: maxY * 1.15,
                        gridData: grid,
                        titlesData: titles,
                        borderData: FlBorderData(show: false),
                        lineBarsData: [
                          LineChartBarData(
                            spots: spots,
                            isCurved: true,
                            curveSmoothness: 0.35,
                            preventCurveOverShooting: true,
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
                              color: AppColors.primary.withValues(alpha: 0.10),
                            ),
                          ),
                        ],
                        lineTouchData: LineTouchData(
                          touchTooltipData: LineTouchTooltipData(
                            getTooltipColor: (_) => AppColors.text,
                            getTooltipItems: (touchedSpots) {
                              return touchedSpots.map((spot) {
                                final idx = spot.x.toInt() - lead;
                                final valPaise = idx >= 0 && idx < dataCount
                                    ? (useBars
                                          ? bars[idx].amount
                                          : cash[idx].income)
                                    : 0;
                                final period = idx >= 0 && idx < dataCount
                                    ? _formatChartLabel(
                                        useBars
                                            ? bars[idx].label
                                            : cash[idx].label,
                                      )
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
                );
              },
            ),
        ],
      ),
    );
  }
}

/// Stands in for a period-specific chart while the response for the selected
/// period/outlet is still in flight, so old labels never sit under a new title.
class _StaleChartPlaceholder extends StatelessWidget {
  const _StaleChartPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const AppCard(
      padding: EdgeInsets.all(16),
      child: SizedBox(
        height: 180,
        width: double.infinity,
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      ),
    );
  }
}

class _CashFlowChart extends StatelessWidget {
  final List<CashPoint> cash;

  /// Which period the totals cover, e.g. "This week".
  final String periodLabel;

  const _CashFlowChart({required this.cash, required this.periodLabel});

  @override
  Widget build(BuildContext context) {
    if (cash.isEmpty) return const SizedBox.shrink();

    final totalIncome = cash.fold<int>(0, (s, c) => s + c.income);
    final totalExpenses = cash.fold<int>(0, (s, c) => s + c.expenses);
    final net = totalIncome - totalExpenses;
    final spentPct = totalIncome > 0
        ? ((totalExpenses / totalIncome) * 100).round().clamp(0, 100)
        : 0;
    final keptPct = 100 - spentPct;
    // Spending beyond what was collected: the bar then shows how much of the
    // spend is covered so far and how much is still to cover.
    final shortfall = totalExpenses > totalIncome;
    final coveredPct = (totalIncome <= 0 || totalExpenses <= 0)
        ? 0
        : ((totalIncome / totalExpenses) * 100).round().clamp(1, 99);
    final yetPct = 100 - coveredPct;
    final leftPct = shortfall ? coveredPct : spentPct;
    final rightPct = shortfall ? yetPct : keptPct;
    final leftColor = shortfall ? AppColors.success : AppColors.warning;
    final rightColor = shortfall ? AppColors.danger : AppColors.success;
    final leftLabel = shortfall
        ? 'Covered ${CurrencyFormatter.format(totalIncome)} · $coveredPct%'
        : 'Spent ${CurrencyFormatter.format(totalExpenses)} · $spentPct%';
    final rightLabel = shortfall
        ? 'Yet to cover ${CurrencyFormatter.format(totalExpenses - totalIncome)} · $yetPct%'
        : 'Kept ${CurrencyFormatter.format(net)} · $keptPct%';

    final netLabel = net < 0
        ? '-${CurrencyFormatter.format(net.abs())}'
        : CurrencyFormatter.format(net);

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Collected vs expenses',
            style: TextStyle(
              fontFamily: AppTextStyles.fontBody,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 2),
          Text(periodLabel, style: AppTextStyles.hint),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _buildKpi(
                  'Collected',
                  CurrencyFormatter.format(totalIncome),
                  AppColors.primary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildKpi(
                  'Spent',
                  CurrencyFormatter.format(totalExpenses),
                  AppColors.warning,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildKpi(
                  'Net',
                  netLabel,
                  net < 0 ? AppColors.danger : AppColors.success,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (totalIncome <= 0 && totalExpenses <= 0)
            const Text(
              'Nothing collected or spent in this period',
              style: AppTextStyles.hint,
            )
          else ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: double.infinity,
                height: 12,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (leftPct > 0)
                      Expanded(
                        flex: leftPct,
                        child: ColoredBox(color: leftColor),
                      ),
                    if (rightPct > 0)
                      Expanded(
                        flex: rightPct,
                        child: ColoredBox(color: rightColor),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            // A Wrap, not a Row: with large amounts on a narrow phone the two
            // labels drop onto separate lines instead of overflowing.
            SizedBox(
              width: double.infinity,
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 12,
                runSpacing: 2,
                children: [
                  Text(
                    leftLabel,
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontBody,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: leftColor,
                    ),
                  ),
                  Text(
                    rightLabel,
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontBody,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: rightColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildKpi(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontFamily: AppTextStyles.fontBody,
            fontSize: 12,
            color: AppColors.mutedText,
          ),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            maxLines: 1,
            style: TextStyle(
              fontFamily: AppTextStyles.fontDisplay,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: color,
            ),
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
          radius: 20,
          showTitle: false,
        ),
      );
    } else {
      if (pendingCount > 0) {
        sections.add(
          PieChartSectionData(
            value: pendingCount.toDouble(),
            color: AppColors.neutralText,
            radius: 20,
            showTitle: false,
          ),
        );
      }
      if (inProgressCount > 0) {
        sections.add(
          PieChartSectionData(
            value: inProgressCount.toDouble(),
            color: AppColors.primary,
            radius: 20,
            showTitle: false,
          ),
        );
      }
      if (readyCount > 0) {
        sections.add(
          PieChartSectionData(
            value: readyCount.toDouble(),
            color: AppColors.violet,
            radius: 20,
            showTitle: false,
          ),
        );
      }
      if (completedCount > 0) {
        sections.add(
          PieChartSectionData(
            value: completedCount.toDouble(),
            color: AppColors.success,
            radius: 20,
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
                    width: 132,
                    height: 132,
                    child: PieChart(
                      PieChartData(
                        sectionsSpace: 2.5,
                        centerSpaceRadius: 42,
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
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: AppColors.text,
                          height: 1.0,
                        ),
                      ),
                      const Text(
                        'orders',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppColors.mutedText,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  children: [
                    _buildLegendItem(
                      color: AppColors.neutralText,
                      label: 'Pending',
                      count: pendingCount,
                      total: total,
                    ),
                    const SizedBox(height: 12),
                    _buildLegendItem(
                      color: AppColors.primary,
                      label: 'In progress',
                      count: inProgressCount,
                      total: total,
                    ),
                    const SizedBox(height: 12),
                    _buildLegendItem(
                      color: AppColors.violet,
                      label: 'Ready',
                      count: readyCount,
                      total: total,
                    ),
                    const SizedBox(height: 12),
                    _buildLegendItem(
                      color: AppColors.success,
                      label: 'Delivered',
                      count: completedCount,
                      total: total,
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
    required int total,
  }) {
    final pct = total > 0 ? (count / total * 100).round() : 0;
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: AppTextStyles.fontBody,
              fontSize: 13,
              fontWeight: FontWeight.w500,
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
        SizedBox(
          width: 40,
          child: Text(
            '$pct%',
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontFamily: AppTextStyles.fontBody,
              fontSize: 12,
              color: AppColors.mutedText,
            ),
          ),
        ),
      ],
    );
  }
}

class _SalesByServiceChart extends StatelessWidget {
  final List<ServiceMixItem> serviceMix;
  final PeriodRange range;
  final bool loading;
  final bool failed;
  final ValueChanged<PeriodRange> onRange;
  final VoidCallback onRetry;

  const _SalesByServiceChart({
    required this.serviceMix,
    required this.range,
    required this.loading,
    required this.failed,
    required this.onRange,
    required this.onRetry,
  });

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
          Text(
            'Your busiest services · ${range.label.toLowerCase()}',
            style: AppTextStyles.hint,
          ),
          const SizedBox(height: 12),
          PeriodFilter(
            key: const ValueKey('filter-salesByService'),
            value: range,
            onChanged: onRange,
          ),
          const SizedBox(height: 16),
          if (loading || failed || serviceMix.isEmpty)
            _CardStateBox(
              loading: loading,
              failed: failed,
              emptyText: 'No sales in this period',
              onRetry: onRetry,
            )
          else
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

/// The five newest orders, from what is on the phone (so it works offline).
/// In the combined All outlets view each row names its outlet.
class _RecentOrdersCard extends StatelessWidget {
  final List<Order> orders;
  final OutletScope? scope;
  final VoidCallback? onViewAll;

  const _RecentOrdersCard({
    required this.orders,
    required this.scope,
    required this.onViewAll,
  });

  static const _shown = 5;

  String? _outletLabel(Order order) {
    final s = scope;
    if (s == null || !s.allOutlets || s.allowed.length <= 1) return null;
    final id = order.outletId;
    if (id == null || id.isEmpty) return 'Organization-wide';
    for (final o in s.allowed) {
      if (o.id == id) return o.displayName;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final newest = [...orders]
      ..sort((a, b) {
        if (a.hasValidCreatedDate && !b.hasValidCreatedDate) return -1;
        if (!a.hasValidCreatedDate && b.hasValidCreatedDate) return 1;
        if (!a.hasValidCreatedDate && !b.hasValidCreatedDate) return 0;
        return b.createdAt.compareTo(a.createdAt);
      });
    final recent = newest.take(_shown).toList();

    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Recent orders',
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontBody,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
              ),
              if (onViewAll != null)
                TextActionButton(label: 'View all', onPressed: onViewAll),
            ],
          ),
          for (var i = 0; i < recent.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: AppColors.divider),
            _row(context, recent[i]),
          ],
        ],
      ),
    );
  }

  Widget _row(BuildContext context, Order order) {
    final outlet = _outletLabel(order);
    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          settings: const RouteSettings(name: 'order_detail'),
          builder: (_) => OrderDetailScreen(initialOrder: order),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 10, 8, 10),
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
                        order.displayCode,
                        style: const TextStyle(
                          fontFamily: AppTextStyles.fontDisplay,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.text,
                        ),
                      ),
                      StatusPill.fromStatus(order.status),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${order.name.isNotEmpty ? order.name : 'Walk-in Customer'}'
                    '${outlet != null ? ' · $outlet' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
                fontSize: 14.5,
                fontWeight: FontWeight.w800,
                color: AppColors.text,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
