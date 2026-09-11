import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:myshop/core/constants/app_colors.dart';
import 'package:myshop/core/sync/sync_manager.dart';
import 'package:myshop/core/theme/text_styles.dart';
import 'package:myshop/core/utils/currency_formatter.dart';
import 'package:myshop/core/utils/date_formatter.dart';
import 'package:myshop/features/auth/bloc/auth_bloc.dart';
import 'package:myshop/features/auth/bloc/auth_state.dart';
import 'package:myshop/features/orders/bloc/orders_bloc.dart';
import 'package:myshop/features/orders/bloc/orders_event.dart';
import 'package:myshop/features/orders/bloc/orders_state.dart';
import 'package:myshop/features/orders/data/models/order_model.dart';
import 'package:myshop/features/orders/presentation/dialogs/collect_payment_dialog.dart';
import 'package:myshop/features/orders/presentation/order_detail_screen.dart';
import 'package:myshop/features/pos/bloc/cart_bloc.dart';
import 'package:myshop/features/pos/bloc/cart_event.dart';
import 'package:myshop/features/pos/presentation/customer_details_screen.dart';
import 'package:myshop/features/profile/presentation/profile_screen.dart';
import 'package:myshop/features/shell/presentation/store_switcher_dialog.dart';
import 'package:myshop/shared/widgets/app_card.dart';
import 'package:myshop/shared/widgets/empty_state.dart';
import 'package:myshop/shared/widgets/filter_chip.dart';
import 'package:myshop/shared/widgets/status_pill.dart';
import 'package:myshop/shared/widgets/sticky_header_delegate.dart';
import 'package:myshop/shared/widgets/sync_status_bar.dart';

class OrdersListScreen extends StatefulWidget {
  const OrdersListScreen({super.key});

  @override
  State<OrdersListScreen> createState() => _OrdersListScreenState();
}

class _OrdersListScreenState extends State<OrdersListScreen> {
  final TextEditingController _searchController = TextEditingController();
  SyncStatus? _lastSyncStatus;

  // Search box (44) + gap (12) + filter chip row (44) + container padding
  // (14 top, 12 bottom) + divider (1) — the fixed height of the pinned
  // sliver header. Keep in sync with _buildStickyFilters below.
  static const double _stickyHeaderHeight = 127;

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

  /// This screen only reads the cache on its own initState (once) or an
  /// explicit pull-to-refresh — it never sees a sync that completes on its
  /// own, e.g. the fire-and-forget SyncEngine.trigger() fired right after
  /// creating an order in PosRepository.createOrderOptimistic. Without this,
  /// a just-placed order can sit showing its LOCAL-xxx placeholder here even
  /// after the sync that resolves it to a real order code has already
  /// finished, until the user happens to trigger another load. Re-reading
  /// the cache (no network call — LoadOrdersEvent is cache-only) whenever
  /// any sync anywhere just finished successfully closes that gap.
  void _onSyncStateChanged() {
    final status = SyncManager.instance.value.status;
    if (status == SyncStatus.synced && _lastSyncStatus != SyncStatus.synced) {
      context.read<OrdersBloc>().add(LoadOrdersEvent());
    }
    _lastSyncStatus = status;
  }

  void _startNewOrder(BuildContext context) {
    context.read<CartBloc>().add(ResetSaleEvent());
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const CustomerDetailsScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthBloc>().state;
    String storeSubtitle = '';
    final hasMultipleStores =
        authState is AuthenticatedState && authState.availableStores.length > 1;
    if (authState is AuthenticatedState) {
      storeSubtitle =
          '${authState.currentStore.storeName} · ${authState.user.displayName}';
    }

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        titleSpacing: 20,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Dashboard',
              style: TextStyle(
                fontFamily: AppTextStyles.fontDisplay,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.6,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 3),
            InkWell(
              onTap: hasMultipleStores
                  ? () => StoreSwitcherDialog.show(context)
                  : null,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      storeSubtitle,
                      style: AppTextStyles.hint,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (hasMultipleStores) ...[
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.arrow_drop_down,
                      size: 16,
                      color: AppColors.mutedText,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const ProfileScreen())),
              child: Container(
                width: 34,
                height: 34,
                decoration: const BoxDecoration(
                  color: AppColors.primaryTint,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    authState is AuthenticatedState
                        ? _initials(authState.user.displayName)
                        : '?',
                    style: const TextStyle(
                      fontFamily: AppTextStyles.fontDisplay,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
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

          final allOrders = state.allOrders;
          final filteredOrders = state.filteredOrders;

          // Counts for stat cards and filter chips
          final allCount = allOrders.length;
          final toCollectCount = allOrders
              .where((o) => o.balanceDue > 0 && !o.isDelivered)
              .length;
          final pendingCount = allOrders
              .where((o) => o.status.toLowerCase() == 'pending')
              .length;
          final inProgressCount = allOrders
              .where((o) => o.status.toLowerCase() == 'in progress')
              .length;
          final readyCount = allOrders
              .where((o) => o.status.toLowerCase() == 'ready')
              .length;
          final deliveredCount = allOrders
              .where((o) => o.status.toLowerCase() == 'delivered')
              .length;

          return Column(
            children: [
              // Live Sync Status Banner — kept outside the scroll area so its
              // animated height never fights with the sliver layout below.
              SyncStatusBar(onSyncNow: () => _refreshAndAwait(context)),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () => _refreshAndAwait(context),
                  child: CustomScrollView(
                    slivers: [
                      // Stat cards — this is the part that scrolls away.
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                          child: Row(
                            children: [
                              Expanded(
                                child: _StatCard(
                                  label: 'Total orders',
                                  value: allCount,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _StatCard(
                                  label: 'Pending',
                                  value: pendingCount,
                                  valueColor: const Color(0xFF92400E),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                          child: Row(
                            children: [
                              Expanded(
                                child: _StatCard(
                                  label: 'In progress',
                                  value: inProgressCount,
                                  valueColor: AppColors.primary,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _StatCard(
                                  label: 'Completed',
                                  value: deliveredCount,
                                  valueColor: AppColors.success,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Search + filters — pinned once stat cards scroll past.
                      SliverPersistentHeader(
                        pinned: true,
                        delegate: StickyHeaderDelegate(
                          height: _stickyHeaderHeight,
                          child: _buildStickyFilters(
                            context,
                            state: state,
                            allCount: allCount,
                            toCollectCount: toCollectCount,
                            pendingCount: pendingCount,
                            inProgressCount: inProgressCount,
                            readyCount: readyCount,
                            deliveredCount: deliveredCount,
                          ),
                        ),
                      ),

                      // Orders list / empty states
                      ..._buildListSlivers(
                        context,
                        allOrders: allOrders,
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
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.primary,
        onPressed: () => _startNewOrder(context),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length >= 2) return (parts[0][0] + parts[1][0]).toUpperCase();
    return parts[0].substring(0, parts[0].length >= 2 ? 2 : 1).toUpperCase();
  }

  Widget _buildStickyFilters(
    BuildContext context, {
    required OrdersState state,
    required int allCount,
    required int toCollectCount,
    required int pendingCount,
    required int inProgressCount,
    required int readyCount,
    required int deliveredCount,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          color: AppColors.surface,
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
          child: Column(
            children: [
              // Search box
              Container(
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  border: Border.all(color: AppColors.controlBorder),
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 13),
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
                          hintText: 'Search order, customer or phone',
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
                          context.read<OrdersBloc>().add(
                            SearchOrdersEvent(val),
                          );
                        },
                      ),
                    ),
                    if (_searchController.text.isNotEmpty)
                      InkWell(
                        onTap: () {
                          _searchController.clear();
                          context.read<OrdersBloc>().add(SearchOrdersEvent(''));
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
              const SizedBox(height: 12),

              // Filter chips row
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    AppFilterChip(
                      label: 'All $allCount',
                      isSelected: state.activeFilter == 'all',
                      onTap: () => _setFilter(context, 'all'),
                    ),
                    const SizedBox(width: 8),
                    AppFilterChip(
                      label: 'To collect $toCollectCount',
                      isSelected: state.activeFilter == 'to_collect',
                      onTap: () => _setFilter(context, 'to_collect'),
                    ),
                    const SizedBox(width: 8),
                    AppFilterChip(
                      label: 'Pending $pendingCount',
                      isSelected: state.activeFilter == 'pending',
                      onTap: () => _setFilter(context, 'pending'),
                    ),
                    const SizedBox(width: 8),
                    AppFilterChip(
                      label: 'In progress $inProgressCount',
                      isSelected: state.activeFilter == 'in_progress',
                      onTap: () => _setFilter(context, 'in_progress'),
                    ),
                    const SizedBox(width: 8),
                    AppFilterChip(
                      label: 'Ready $readyCount',
                      isSelected: state.activeFilter == 'ready',
                      onTap: () => _setFilter(context, 'ready'),
                    ),
                    const SizedBox(width: 8),
                    AppFilterChip(
                      label: 'Delivered $deliveredCount',
                      isSelected: state.activeFilter == 'delivered',
                      onTap: () => _setFilter(context, 'delivered'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(color: AppColors.border, height: 1),
      ],
    );
  }

  void _setFilter(BuildContext context, String filter) {
    context.read<OrdersBloc>().add(FilterOrdersEvent(filter));
  }

  /// Dispatches RefreshOrdersEvent and waits for it to finish, so both the
  /// pull-to-refresh spinner and the "Sync now"/"Retry" tap show the real
  /// sync duration instead of returning instantly.
  Future<void> _refreshAndAwait(BuildContext context) async {
    final bloc = context.read<OrdersBloc>();
    bloc.add(RefreshOrdersEvent());
    await bloc.stream.firstWhere((s) => !s.isLoading);
  }

  List<Widget> _buildListSlivers(
    BuildContext context, {
    required List<Order> allOrders,
    required List<Order> filteredOrders,
  }) {
    if (allOrders.isEmpty) {
      // Screen 9a: Empty state
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
      // Screen 9b: No search / filter results
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: EmptyState(
                icon: Icons.search_off_outlined,
                title: 'No orders match',
                subtitle:
                    'Try clearing your search query or switching filters.',
                actionLabel: 'Clear filters',
                onAction: () {
                  _searchController.clear();
                  context.read<OrdersBloc>().add(SearchOrdersEvent(''));
                  context.read<OrdersBloc>().add(FilterOrdersEvent('all'));
                },
              ),
            ),
          ),
        ),
      ];
    }

    return [
      SliverPadding(
        padding: const EdgeInsets.all(20),
        sliver: SliverList.separated(
          itemCount: filteredOrders.length,
          separatorBuilder: (_, _) => const SizedBox(height: 11),
          itemBuilder: (context, index) {
            final order = filteredOrders[index];
            return _buildOrderCard(context, order);
          },
        ),
      ),
    ];
  }

  Widget _buildOrderCard(BuildContext context, Order order) {
    final hasBalance = order.balanceDue > 0;
    final isReady = order.status.toLowerCase() == 'ready';

    return AppCard(
      padding: const EdgeInsets.all(15),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => OrderDetailScreen(initialOrder: order),
          ),
        );
      },
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left: code, status, customer, details
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
                        if (!order.isSynced)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF3CD),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: const Color(0xFFE9C46A),
                              ),
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
                    const SizedBox(height: 4),
                    Text(
                      '${order.lines.length} ${order.lines.length == 1 ? "service" : "services"} · ready ${DateFormatter.formatShort(order.due)}',
                      style: AppTextStyles.hint,
                    ),
                  ],
                ),
              ),

              // Right: total amount and balance pill
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
                  const SizedBox(height: 7),
                  if (hasBalance)
                    StatusPill(
                      label:
                          '${CurrencyFormatter.format(order.balanceDue)} due',
                      variant: PillVariant.balanceDue,
                    )
                  else
                    const StatusPill(label: 'Paid', variant: PillVariant.paid),
                ],
              ),
            ],
          ),

          // Quick action: one constant "Collect payment & deliver" button
          // once the order is ready — the dialog itself branches on whether
          // a balance is due, instead of this card choosing between two
          // different dialogs.
          if (isReady && !order.isDelivered) ...[
            const SizedBox(height: 13),
            InkWell(
              onTap: () {
                CollectPaymentDialog.show(context, order: order);
              },
              borderRadius: BorderRadius.circular(9),
              child: Container(
                constraints: const BoxConstraints(minHeight: 46),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.primary, width: 1.5),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.payments_outlined,
                      size: 17,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      hasBalance
                          ? 'Collect ${CurrencyFormatter.format(order.balanceDue)} & deliver'
                          : 'Collect payment & deliver',
                      style: const TextStyle(
                        fontFamily: AppTextStyles.fontBody,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final int value;
  final Color? valueColor;

  const _StatCard({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.inset,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTextStyles.hint),
          const SizedBox(height: 4),
          Text(
            '$value',
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
}
