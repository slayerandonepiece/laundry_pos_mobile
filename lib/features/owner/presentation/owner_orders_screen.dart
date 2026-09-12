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
import 'package:myshop/shared/widgets/app_card.dart';
import 'package:myshop/shared/widgets/empty_state.dart';
import 'package:myshop/shared/widgets/filter_chip.dart';
import 'package:myshop/shared/widgets/status_pill.dart';
import 'package:myshop/shared/widgets/sync_status_bar.dart';

class OwnerOrdersScreen extends StatefulWidget {
  const OwnerOrdersScreen({super.key});

  @override
  State<OwnerOrdersScreen> createState() => _OwnerOrdersScreenState();
}

class _OwnerOrdersScreenState extends State<OwnerOrdersScreen> {
  final TextEditingController _searchController = TextEditingController();
  SyncStatus? _lastSyncStatus;

  String _selectedPeriod = 'today'; // 'today' | '7d' | '30d'
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
    context.read<OrdersBloc>().add(LoadOrdersEvent());
    SyncManager.instance.addListener(_onSyncStateChanged);
  }

  @override
  void dispose() {
    SyncManager.instance.removeListener(_onSyncStateChanged);
    _searchController.dispose();
    super.dispose();
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

  void _startNewOrder(BuildContext context) {
    context.read<CartBloc>().add(ResetSaleEvent());
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
        final matchesId = order.id.toLowerCase().contains(q);
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
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        titleSpacing: 20,
        title: const Text(
          'Orders',
          style: TextStyle(
            fontFamily: AppTextStyles.fontDisplay,
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
            color: AppColors.text,
          ),
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
                              // 1. Title + Period selector
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
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
                                    onPeriodChanged: (val) {
                                      setState(() {
                                        _selectedPeriod = val;
                                        _activeQuickFilter = 'selected_dates';
                                      });
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),

                              // 2. Stats cards
                              _buildPrimaryStatCard(
                                orderValue: orderValue,
                                count: filteredOrders.length,
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildSecondaryStatCard(
                                      label: 'Collected',
                                      value: CurrencyFormatter.format(
                                        collected,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _buildSecondaryStatCard(
                                      label: 'To collect',
                                      value: CurrencyFormatter.format(
                                        toCollect,
                                      ),
                                      valueColor: toCollect > 0
                                          ? AppColors.danger
                                          : AppColors.text,
                                    ),
                                  ),
                                ],
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
                                              child: Text('Partial'),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                            ],
                          ),
                        ),
                      ),

                      // Order list or empty states
                      ..._buildOrdersSlivers(
                        context,
                        allOrders: state.allOrders,
                        filteredOrders: filteredOrders,
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

  Widget _buildPrimaryStatCard({required int orderValue, required int count}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Order value',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFFD9E7FF),
            ),
          ),
          const SizedBox(height: 9),
          Text(
            CurrencyFormatter.format(orderValue),
            style: const TextStyle(
              fontFamily: AppTextStyles.fontDisplay,
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            '$count matching ${count == 1 ? "order" : "orders"}',
            style: const TextStyle(fontSize: 11, color: Color(0xFFD9E7FF)),
          ),
        ],
      ),
    );
  }

  Widget _buildSecondaryStatCard({
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return AppCard(
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppColors.mutedText),
          ),
          const SizedBox(height: 9),
          Text(
            value,
            style: TextStyle(
              fontFamily: AppTextStyles.fontDisplay,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: valueColor ?? AppColors.text,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildOrdersSlivers(
    BuildContext context, {
    required List<Order> allOrders,
    required List<Order> filteredOrders,
  }) {
    if (allOrders.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: EmptyState(
                icon: Icons.receipt_long_outlined,
                title: 'No orders yet',
                subtitle: 'Orders will appear here as soon as you take a sale.',
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
                      subtitle: 'Try changing your date range, search query, or status filters.',
                      actionLabel: 'Clear filters',
                      onAction: () {
                        _searchController.clear();
                        setState(() {
                          _searchQuery = '';
                          _selectedPeriod = 'today';
                          _activeQuickFilter = 'selected_dates';
                          _selectedWorkStatus = 'all';
                          _selectedPaymentStatus = 'all';
                        });
                      },
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

  const _OwnerOrderCard({required this.order, required this.onTap});

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
                      order.orderCode,
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
                  '${order.lines.length} ${order.lines.length == 1 ? "service" : "services"} · due ${DateFormatter.formatShort(order.due)}',
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
