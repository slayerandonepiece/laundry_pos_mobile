import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:myshop/core/constants/app_colors.dart';
import 'package:myshop/core/sync/sync_manager.dart';
import 'package:myshop/core/theme/text_styles.dart';
import 'package:myshop/core/utils/currency_formatter.dart';
import 'package:myshop/core/utils/date_formatter.dart';
import 'package:myshop/features/orders/bloc/orders_bloc.dart';
import 'package:myshop/features/orders/bloc/orders_event.dart';
import 'package:myshop/features/orders/bloc/orders_state.dart';
import 'package:myshop/features/orders/data/models/order_model.dart';
import 'package:myshop/features/orders/presentation/order_detail_screen.dart';
import 'package:myshop/features/pos/bloc/cart_bloc.dart';
import 'package:myshop/features/pos/bloc/cart_event.dart';
import 'package:myshop/features/pos/presentation/customer_details_screen.dart';
import 'package:myshop/features/shell/bloc/outlet_scope_cubit.dart';
import 'package:myshop/features/shell/data/models/outlet_model.dart';
import 'package:myshop/shared/widgets/app_card.dart';
import 'package:myshop/shared/widgets/empty_state.dart';
import 'package:myshop/shared/widgets/filter_chip.dart';
import 'package:myshop/shared/widgets/outlet_title_switcher.dart';
import 'package:myshop/shared/widgets/status_pill.dart';
import 'package:myshop/shared/widgets/sync_status_bar.dart';

class OwnerOrdersScreen extends StatefulWidget {
  final ValueNotifier<int>? resetSignal;

  const OwnerOrdersScreen({super.key, this.resetSignal});

  @override
  State<OwnerOrdersScreen> createState() => _OwnerOrdersScreenState();
}

class _OwnerOrdersScreenState extends State<OwnerOrdersScreen> {
  final TextEditingController _searchController = TextEditingController();
  SyncStatus? _lastSyncStatus;

  String _selectedPeriod = '30d'; // 'today' | '7d' | '30d' | 'quarter' | 'custom'
  DateTime? _customFrom;
  DateTime? _customTo;
  String _activeQuickFilter =
      'selected_dates'; // 'selected_dates' | 'due_today' | 'late'
  String _searchQuery = '';
  String _selectedWorkStatus =
      'all'; // 'all' | 'pending' | 'in_progress' | 'ready' | 'delivered'
  String _selectedPaymentStatus =
      'all'; // 'all' | 'paid' | 'unpaid' | 'partial'

  @override
  void initState() {
    super.initState();
    widget.resetSignal?.addListener(_onTabLeft);
    context.read<OrdersBloc>().add(LoadOrdersEvent());
    SyncManager.instance.addListener(_onSyncStateChanged);
  }

  @override
  void dispose() {
    widget.resetSignal?.removeListener(_onTabLeft);
    SyncManager.instance.removeListener(_onSyncStateChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onTabLeft() {
    if (_selectedPeriod != '30d' ||
        _customFrom != null ||
        _customTo != null ||
        _activeQuickFilter != 'selected_dates') {
      setState(() {
        _selectedPeriod = '30d';
        _customFrom = null;
        _customTo = null;
        _activeQuickFilter = 'selected_dates';
      });
    }
  }

  void _clearAllFilters() {
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _selectedPeriod = '30d';
      _activeQuickFilter = 'selected_dates';
      _selectedWorkStatus = 'all';
      _selectedPaymentStatus = 'all';
      _customFrom = null;
      _customTo = null;
    });
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
  }

  Widget _buildCustomDateSelector() {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
    );
  }

  void _onSyncStateChanged() {
    final status = SyncManager.instance.value.status;
    if (status == SyncStatus.synced && _lastSyncStatus != SyncStatus.synced) {
      context.read<OrdersBloc>().add(LoadOrdersEvent());
    }
    _lastSyncStatus = status;
  }

  Future<void> _refreshAndAwait(BuildContext context) async {
    final bloc = context.read<OrdersBloc>();
    bloc.add(RefreshOrdersEvent());
    await bloc.stream.firstWhere((s) => !s.isLoading);
  }

  Future<void> _startNewOrder(BuildContext context) async {
    final scope = context.read<OutletScopeCubit>().state;
    final String? chosenOutletId;

    if (scope.allOutlets) {
      chosenOutletId = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => _OutletSelectionSheet(outlets: scope.allowed),
      );
      if (chosenOutletId == null) {
        return;
      }
    } else {
      chosenOutletId = scope.activeOutletId;
    }

    if (!context.mounted) return;
    context.read<CartBloc>().add(ResetSaleEvent(outletId: chosenOutletId));
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const CustomerDetailsScreen()));
  }

  DateTime _startOfDay(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  bool _matchesPeriod(Order order, String period, DateTime todayStart) {
    final orderDate = _startOfDay(order.createdAt);
    final tomorrowStart = todayStart.add(const Duration(days: 1));

    switch (period) {
      case 'today':
        return orderDate.isAtSameMomentAs(todayStart);
      case '7d':
        final start7d = todayStart.subtract(const Duration(days: 6));
        return !orderDate.isBefore(start7d) &&
            orderDate.isBefore(tomorrowStart);
      case '30d':
        final start30d = todayStart.subtract(const Duration(days: 29));
        final isLast30d =
            !orderDate.isBefore(start30d) && orderDate.isBefore(tomorrowStart);
        final isThisMonth =
            orderDate.year == todayStart.year &&
            orderDate.month == todayStart.month;
        return isLast30d || isThisMonth;
      case 'quarter':
        final quarterStart = DateTime(
          todayStart.year,
          ((todayStart.month - 1) ~/ 3) * 3 + 1,
          1,
        );
        final nextQuarterStart = DateTime(
          todayStart.year,
          ((todayStart.month - 1) ~/ 3) * 3 + 4,
          1,
        );
        return !orderDate.isBefore(quarterStart) &&
            orderDate.isBefore(nextQuarterStart);
      case 'custom':
        if (_customFrom == null || _customTo == null) {
          final start30d = todayStart.subtract(const Duration(days: 29));
          final isLast30d =
              !orderDate.isBefore(start30d) && orderDate.isBefore(tomorrowStart);
          final isThisMonth =
              orderDate.year == todayStart.year &&
              orderDate.month == todayStart.month;
          return isLast30d || isThisMonth;
        }
        final fromDate = _startOfDay(_customFrom!);
        final toDateTomorrow =
            _startOfDay(_customTo!).add(const Duration(days: 1));
        return !orderDate.isBefore(fromDate) &&
            orderDate.isBefore(toDateTomorrow);
      default:
        return true;
    }
  }

  List<Order> _filterOrders(List<Order> allOrders) {
    final now = DateTime.now();
    final todayStart = _startOfDay(now);

    return allOrders.where((order) {
      // 1. Quick filter / Date range
      if (_activeQuickFilter == 'due_today') {
        final dueDate = _startOfDay(order.dueDateTime);
        if (!dueDate.isAtSameMomentAs(todayStart)) {
          return false;
        }
      } else if (_activeQuickFilter == 'late') {
        final dueDate = _startOfDay(order.dueDateTime);
        if (!dueDate.isBefore(todayStart) || order.isDelivered) {
          return false;
        }
      } else {
        // 'selected_dates'
        if (!_matchesPeriod(order, _selectedPeriod, todayStart)) {
          return false;
        }
      }

      // 2. Search query (matches id, name, phone)
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase().trim();
        final matchesId = order.displayCode.toLowerCase().contains(q);
        final matchesName = order.name.toLowerCase().contains(q);
        final matchesPhone = order.phone.contains(q);
        if (!matchesId && !matchesName && !matchesPhone) {
          return false;
        }
      }

      // 3. Work status filter
      switch (_selectedWorkStatus) {
        case 'pending':
          if (!order.isPending) return false;
          break;
        case 'in_progress':
          if (!order.isInProgress) return false;
          break;
        case 'ready':
          if (!order.isReady) return false;
          break;
        case 'delivered':
          if (!order.isDelivered) return false;
          break;
        case 'all':
        default:
          break;
      }

      // 4. Payment status filter
      switch (_selectedPaymentStatus) {
        case 'paid':
          if (order.balanceDue != 0) return false;
          break;
        case 'unpaid':
          if (order.paidAmount != 0) return false;
          break;
        case 'partial':
          if (order.paidAmount <= 0 || order.balanceDue <= 0) return false;
          break;
        case 'all':
        default:
          break;
      }

      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final outletScope = context.watch<OutletScopeCubit>().state;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        titleSpacing: 20,
        title: const OutletTitleSwitcher(
          screenLabel: 'Orders',
          showAllOutletsOption: true,
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: IconButton(
              icon: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(Icons.add, color: Colors.white, size: 20),
              ),
              onPressed: () => _startNewOrder(context),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: AppColors.border, height: 1),
        ),
      ),
      body: BlocBuilder<OrdersBloc, OrdersState>(
        builder: (context, state) {
          if (state.isLoading && state.allOrders.isEmpty) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            );
          }

          final filteredOrders = _filterOrders(state.allOrders);

          // Compute stats
          int orderValue = 0;
          int collected = 0;
          int toCollect = 0;
          for (final order in filteredOrders) {
            orderValue += order.totalAmount;
            collected += (order.totalAmount - order.balanceDue);
            toCollect += order.balanceDue;
          }

          return Column(
            children: [
              SyncStatusBar(onSyncNow: () => _refreshAndAwait(context)),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () => _refreshAndAwait(context),
                  child: CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Unified Sales summary card
                              _buildSalesSummaryCard(
                                orderValue: orderValue,
                                count: filteredOrders.length,
                                collected: collected,
                                toCollect: toCollect,
                              ),
                              const SizedBox(height: 16),

                              // 3. Quick filter chips
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    AppFilterChip(
                                      label: 'Selected dates',
                                      isSelected:
                                          _activeQuickFilter ==
                                          'selected_dates',
                                      onTap: () => setState(
                                        () => _activeQuickFilter =
                                            'selected_dates',
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    AppFilterChip(
                                      label: 'Due today',
                                      isSelected:
                                          _activeQuickFilter == 'due_today',
                                      onTap: () => setState(
                                        () => _activeQuickFilter = 'due_today',
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    AppFilterChip(
                                      label: 'Late',
                                      isSelected: _activeQuickFilter == 'late',
                                      onTap: () => setState(
                                        () => _activeQuickFilter = 'late',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),

                              // 4. Search box
                              Container(
                                height: 44,
                                decoration: BoxDecoration(
                                  color: AppColors.surface,
                                  border: Border.all(
                                    color: AppColors.controlBorder,
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 13,
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.search,
                                      size: 19,
                                      color: AppColors.mutedText,
                                    ),
                                    const SizedBox(width: 9),
                                    Expanded(
                                      child: TextField(
                                        controller: _searchController,
                                        style: const TextStyle(
                                          fontFamily: AppTextStyles.fontBody,
                                          fontSize: 14,
                                          color: AppColors.text,
                                        ),
                                        decoration: const InputDecoration(
                                          hintText:
                                              'Search order, customer or phone',
                                          hintStyle: TextStyle(
                                            fontFamily: AppTextStyles.fontBody,
                                            fontSize: 14,
                                            color: AppColors.faintText,
                                          ),
                                          border: InputBorder.none,
                                          isDense: true,
                                          contentPadding: EdgeInsets.zero,
                                        ),
                                        onChanged: (val) {
                                          setState(() => _searchQuery = val);
                                        },
                                      ),
                                    ),
                                    if (_searchController.text.isNotEmpty)
                                      InkWell(
                                        onTap: () {
                                          _searchController.clear();
                                          setState(() => _searchQuery = '');
                                        },
                                        child: const Icon(
                                          Icons.close,
                                          size: 18,
                                          color: AppColors.mutedText,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 10),

                              // 5. Dropdown filters side by side
                              Row(
                                children: [
                                  Expanded(
                                    child: Container(
                                      height: 40,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppColors.surface,
                                        border: Border.all(
                                          color: AppColors.controlBorder,
                                        ),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: DropdownButtonHideUnderline(
                                        child: DropdownButton<String>(
                                          value: _selectedWorkStatus,
                                          isExpanded: true,
                                          icon: const Icon(
                                            Icons.expand_more,
                                            size: 16,
                                            color: AppColors.mutedText,
                                          ),
                                          style: const TextStyle(
                                            fontFamily: AppTextStyles.fontBody,
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.text,
                                          ),
                                          onChanged: (val) {
                                            if (val != null) {
                                              setState(
                                                () => _selectedWorkStatus = val,
                                              );
                                            }
                                          },
                                          items: const [
                                            DropdownMenuItem(
                                              value: 'all',
                                              child: Text(
                                                'All work statuses',
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            DropdownMenuItem(
                                              value: 'pending',
                                              child: Text('Pending'),
                                            ),
                                            DropdownMenuItem(
                                              value: 'in_progress',
                                              child: Text('In Progress'),
                                            ),
                                            DropdownMenuItem(
                                              value: 'ready',
                                              child: Text('Ready'),
                                            ),
                                            DropdownMenuItem(
                                              value: 'delivered',
                                              child: Text('Delivered'),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Container(
                                      height: 40,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppColors.surface,
                                        border: Border.all(
                                          color: AppColors.controlBorder,
                                        ),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: DropdownButtonHideUnderline(
                                        child: DropdownButton<String>(
                                          value: _selectedPaymentStatus,
                                          isExpanded: true,
                                          icon: const Icon(
                                            Icons.expand_more,
                                            size: 16,
                                            color: AppColors.mutedText,
                                          ),
                                          style: const TextStyle(
                                            fontFamily: AppTextStyles.fontBody,
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.text,
                                          ),
                                          onChanged: (val) {
                                            if (val != null) {
                                              setState(
                                                () => _selectedPaymentStatus =
                                                    val,
                                              );
                                            }
                                          },
                                          items: const [
                                            DropdownMenuItem(
                                              value: 'all',
                                              child: Text(
                                                'All payment statuses',
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            DropdownMenuItem(
                                              value: 'paid',
                                              child: Text('Paid'),
                                            ),
                                            DropdownMenuItem(
                                              value: 'unpaid',
                                              child: Text('Unpaid'),
                                            ),
                                            DropdownMenuItem(
                                              value: 'partial',
                                              child: Text('Part-paid'),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  GestureDetector(
                                    onTap: _clearAllFilters,
                                    child: const Padding(
                                      padding: EdgeInsets.symmetric(
                                        vertical: 4,
                                        horizontal: 2,
                                      ),
                                      child: Text(
                                        'Clear',
                                        style: TextStyle(
                                          fontFamily: AppTextStyles.fontBody,
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.primary,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                            ],
                          ),
                        ),
                      ),

                      // Order list or empty states
                      ..._buildOrdersSlivers(
                        context,
                        allOrders: state.allOrders,
                        filteredOrders: filteredOrders,
                        outletScope: outletScope,
                        loadFailed: state.loadFailed,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSalesSummaryCard({
    required int orderValue,
    required int count,
    required int collected,
    required int toCollect,
  }) {
    final hasTotal = orderValue > 0;
    final progress = hasTotal ? (collected / orderValue).clamp(0.0, 1.0) : 0.0;

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Sales summary',
                style: TextStyle(
                  fontFamily: AppTextStyles.fontDisplay,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
              _PeriodSelector(
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
                    _activeQuickFilter = 'selected_dates';
                  });
                },
              ),
            ],
          ),
          if (_selectedPeriod == 'custom') _buildCustomDateSelector(),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    CurrencyFormatter.format(orderValue),
                    style: const TextStyle(
                      fontFamily: AppTextStyles.fontDisplay,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Total order value',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontBody,
                      fontSize: 12,
                      color: AppColors.mutedText,
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '$count ${count == 1 ? "order" : "orders"}',
                  style: const TextStyle(
                    fontFamily: AppTextStyles.fontBody,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.mutedText,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'Collected',
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontBody,
                            fontSize: 12,
                            color: AppColors.mutedText,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      CurrencyFormatter.format(collected),
                      style: const TextStyle(
                        fontFamily: AppTextStyles.fontDisplay,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: toCollect > 0
                                ? AppColors.danger
                                : AppColors.mutedText,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'To collect',
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontBody,
                            fontSize: 12,
                            color: AppColors.mutedText,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      CurrencyFormatter.format(toCollect),
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontDisplay,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: toCollect > 0
                            ? AppColors.danger
                            : AppColors.text,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 7,
              child: hasTotal
                  ? LayoutBuilder(
                      builder: (context, constraints) {
                        return Stack(
                          children: [
                            Container(
                              color: toCollect > 0
                                  ? AppColors.dangerBg
                                  : AppColors.controlBorder,
                            ),
                            FractionallySizedBox(
                              widthFactor: progress,
                              child: Container(color: AppColors.primary),
                            ),
                          ],
                        );
                      },
                    )
                  : Container(color: AppColors.controlBorder),
            ),
          ),
        ],
      ),
    );
  }

  /// Resolved outlet label for a row, or null to hide the line entirely —
  /// only shown in All-outlets scope with more than one outlet (O5.3).
  String? _resolveOutletLabel(Order order, OutletScope scope) {
    if (!scope.allOutlets || scope.allowed.length <= 1) return null;
    final outletId = order.outletId;
    if (outletId == null || outletId.isEmpty) return 'Organization-wide';
    final matches = scope.allowed.where((o) => o.id == outletId);
    return matches.isEmpty ? null : matches.first.displayName;
  }

  List<Widget> _buildOrdersSlivers(
    BuildContext context, {
    required List<Order> allOrders,
    required List<Order> filteredOrders,
    required OutletScope outletScope,
    bool loadFailed = false,
  }) {
    if (allOrders.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: loadFailed
                  ? const EmptyState(
                      icon: Icons.receipt_long_outlined,
                      title: "Can't load orders",
                      subtitle:
                          "You're offline or the server can't be reached. Pull down to try again.",
                    )
                  : EmptyState(
                      icon: Icons.receipt_long_outlined,
                      title: 'No orders yet',
                      subtitle:
                          'Orders will appear here as soon as you take a sale.',
                      actionLabel: 'Take a sale',
                      onAction: () => _startNewOrder(context),
                    ),
            ),
          ),
        ),
      ];
    }

    if (filteredOrders.isEmpty) {
      final isQuickFilterActive =
          _activeQuickFilter == 'due_today' || _activeQuickFilter == 'late';

      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: isQuickFilterActive
                  ? const EmptyState(
                      icon: Icons.check_circle_outline,
                      title: 'Nothing here yet',
                      subtitle:
                          "Nothing due today or overdue, you're all caught up",
                    )
                  : EmptyState(
                      icon: Icons.search_off_outlined,
                      title: 'No orders match your filters',
                      subtitle:
                          'Try changing your date range, search query, or status filters.',
                      actionLabel: 'Clear filters',
                      onAction: _clearAllFilters,
                    ),
            ),
          ),
        ),
      ];
    }

    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        sliver: SliverList.separated(
          itemCount: filteredOrders.length,
          separatorBuilder: (_, _) => const SizedBox(height: 11),
          itemBuilder: (context, index) {
            final order = filteredOrders[index];
            return _OwnerOrderCard(
              order: order,
              outletLabel: _resolveOutletLabel(order, outletScope),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => OrderDetailScreen(initialOrder: order),
                  ),
                );
              },
            );
          },
        ),
      ),
    ];
  }
}

class _OwnerOrderCard extends StatelessWidget {
  final Order order;
  final VoidCallback onTap;
  final String? outletLabel;

  const _OwnerOrderCard({
    required this.order,
    required this.onTap,
    this.outletLabel,
  });

  Widget _buildPaymentPill() {
    if (order.balanceDue == 0) {
      return const StatusPill(label: 'Paid', variant: PillVariant.paid);
    } else if (order.paidAmount > 0) {
      return StatusPill(
        label: '${CurrencyFormatter.format(order.balanceDue)} due',
        variant: PillVariant.balanceDue,
      );
    } else {
      return const StatusPill(label: 'Unpaid', variant: PillVariant.danger);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(15),
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
                      order.displayCode,
                      style: const TextStyle(
                        fontFamily: AppTextStyles.fontDisplay,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.text,
                      ),
                    ),
                    StatusPill.fromStatus(order.status),
                    _buildPaymentPill(),
                    if (!order.isSynced)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF3CD),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFE9C46A)),
                        ),
                        child: const Text(
                          'Offline',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFB07A00),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  order.name.isNotEmpty ? order.name : 'Walk-in Customer',
                  style: const TextStyle(
                    fontFamily: AppTextStyles.fontBody,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
                if (order.phone.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(order.phone, style: AppTextStyles.hint),
                ],
                const SizedBox(height: 4),
                Text(
                  '${order.lines.length} ${order.lines.length == 1 ? "service" : "services"} · due ${DateFormatter.formatShort(order.due)}'
                  '${outletLabel != null ? ' · $outletLabel' : ''}',
                  style: AppTextStyles.hint,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                CurrencyFormatter.format(order.totalAmount),
                style: const TextStyle(
                  fontFamily: AppTextStyles.fontDisplay,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PeriodSelector extends StatelessWidget {
  final String selectedPeriod;
  final DateTime? customFrom;
  final DateTime? customTo;
  final ValueChanged<String> onPeriodChanged;

  const _PeriodSelector({
    required this.selectedPeriod,
    this.customFrom,
    this.customTo,
    required this.onPeriodChanged,
  });

  static const _labels = {
    'today': 'Today',
    '7d': 'This week',
    '30d': 'This month',
    'quarter': 'This quarter',
    'custom': 'Custom dates',
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
          selectedItemBuilder: (context) {
            return _labels.entries.map((e) {
              String labelText = e.value;
              if (e.key == 'custom' && customFrom != null && customTo != null) {
                labelText =
                    '${DateFormatter.formatShort(customFrom!)} – ${DateFormatter.formatShort(customTo!)}';
              }
              return Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  labelText,
                  style: const TextStyle(
                    fontFamily: AppTextStyles.fontBody,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
              );
            }).toList();
          },
          items: _labels.entries.map((e) {
            return DropdownMenuItem<String>(value: e.key, child: Text(e.value));
          }).toList(),
        ),
      ),
    );
  }
}

class _OutletSelectionSheet extends StatelessWidget {
  final List<Outlet> outlets;

  const _OutletSelectionSheet({required this.outlets});

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final keyboardHeight = mediaQuery.viewInsets.bottom;
    final safeBottom = mediaQuery.viewPadding.bottom > 0
        ? mediaQuery.viewPadding.bottom
        : mediaQuery.padding.bottom;
    final bottomInset = keyboardHeight > 0
        ? keyboardHeight + 16
        : (safeBottom > 0 ? safeBottom + 16 : 26.0);

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 10,
        bottom: bottomInset,
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
            'Select outlet',
            style: TextStyle(
              fontFamily: AppTextStyles.fontDisplay,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 14),
          ...outlets.map(
            (outlet) => _OutletSelectionRow(
              outlet: outlet,
              onTap: () => Navigator.pop(context, outlet.id),
            ),
          ),
        ],
      ),
    );
  }
}

class _OutletSelectionRow extends StatelessWidget {
  final Outlet outlet;
  final VoidCallback onTap;

  const _OutletSelectionRow({required this.outlet, required this.onTap});

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
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.neutralBg,
                ),
                child: Center(
                  child: Text(
                    _initials(outlet.displayName),
                    style: const TextStyle(
                      fontFamily: AppTextStyles.fontDisplay,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.mutedText,
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
                      outlet.displayName,
                      style: const TextStyle(
                        fontFamily: AppTextStyles.fontBody,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      outlet.outletCode,
                      style: const TextStyle(
                        fontFamily: AppTextStyles.fontBody,
                        fontSize: 11.5,
                        color: AppColors.mutedText,
                      ),
                    ),
                  ],
                ),
              ),
              if (outlet.isDefault)
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
            ],
          ),
        ),
      ),
    );
  }
}
