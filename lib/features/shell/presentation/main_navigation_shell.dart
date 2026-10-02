import 'package:myshop/features/orders/presentation/orders_drill_down.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:myshop/core/analytics/app_analytics.dart';
import 'package:myshop/core/constants/app_colors.dart';
import 'package:myshop/core/utils/date_formatter.dart';
import 'package:myshop/features/auth/bloc/auth_bloc.dart';
import 'package:myshop/features/auth/bloc/auth_state.dart';
import 'package:myshop/features/orders/bloc/orders_bloc.dart';
import 'package:myshop/features/orders/bloc/orders_event.dart';
import 'package:myshop/features/orders/presentation/orders_list_screen.dart';
import 'package:myshop/features/owner/bloc/owner_bloc.dart';
import 'package:myshop/features/owner/bloc/owner_event.dart';
import 'package:myshop/features/owner/presentation/more_screen.dart';
import 'package:myshop/features/owner/presentation/owner_dashboard_screen.dart';
import 'package:myshop/features/owner/presentation/owner_orders_screen.dart';
import 'package:myshop/features/pos/bloc/cart_bloc.dart';
import 'package:myshop/features/pos/bloc/cart_event.dart';
import 'package:myshop/features/shell/bloc/outlet_scope_cubit.dart';
import 'package:myshop/shared/widgets/access_notice_strip.dart';
import 'package:myshop/shared/widgets/bottom_nav.dart';

class MainNavigationShell extends StatefulWidget {
  const MainNavigationShell({super.key});

  @override
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell> {
  int _currentIndex = 0;
  final ValueNotifier<int> _dashboardResetSignal = ValueNotifier<int>(0);
  final ValueNotifier<int> _ordersResetSignal = ValueNotifier<int>(0);
  bool _initialScreenLogged = false;

  /// A view the dashboard asks the Orders tab to open; the tab applies it and
  /// clears it.
  final ValueNotifier<OrdersDrillDown?> _ordersDrillDown =
      ValueNotifier<OrdersDrillDown?>(null);

  /// The dashboard's own default request (current month to date, daily
  /// buckets, keyed to the outlet scope), same shape as the dashboard screen
  /// sends.
  LoadDashboardEvent _defaultDashboardEvent(OutletScope scope) {
    final now = DateTime.now();
    final scopeKey = scope.allOutlets
        ? 'all'
        : (scope.activeOutletId ?? 'none');
    return LoadDashboardEvent(
      from: DateFormatter.toIsoDateString(DateTime(now.year, now.month, 1)),
      to: DateFormatter.toIsoDateString(now),
      granularity: 'day',
      refresh: true,
      isDefaultPeriod: true,
      requestKey: 'mtd|$scopeKey',
    );
  }

  LoadOutletRollupsEvent _outletRollupsEvent(OutletScope scope) {
    final now = DateTime.now();
    return LoadOutletRollupsEvent(
      allOutlets: scope.allOutlets,
      from: DateFormatter.toIsoDateString(
        now.subtract(const Duration(days: 1)),
      ),
      to: DateFormatter.toIsoDateString(now),
    );
  }

  @override
  void dispose() {
    _dashboardResetSignal.dispose();
    _ordersResetSignal.dispose();
    _ordersDrillDown.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthBloc>().state;
    final isOwner = authState is AuthenticatedState && authState.isOwner;
    if (!_initialScreenLogged) {
      _initialScreenLogged = true;
      AppAnalytics.screenView(isOwner ? 'dashboard' : 'orders');
    }
    final notice = authState is AuthenticatedState
        ? resolveAccessNotice(authState.currentStore, isOwner: isOwner)
        : null;

    // Orders now has its own "start new order" FAB, so New Sale is no
    // longer a separate screen at all.
    // Employee: [OrdersListScreen] — the only screen, no bottom bar needed.
    // Owner: [OwnerDashboardScreen, OwnerOrdersScreen, MoreScreen]
    final List<Widget> screens = isOwner
        ? [
            OwnerDashboardScreen(
              resetSignal: _dashboardResetSignal,
              onOpenOrders: (filter) {
                if (_currentIndex == 0) {
                  _dashboardResetSignal.value++;
                }
                _ordersDrillDown.value = filter;
                setState(() => _currentIndex = 1);
                context.read<OrdersBloc>().add(LoadOrdersEvent());
              },
            ),
            OwnerOrdersScreen(
              resetSignal: _ordersResetSignal,
              drillDown: _ordersDrillDown,
            ),
            const MoreScreen(),
          ]
        : [const OrdersListScreen()];

    // Safety check if index exceeds screens length after role switch
    if (_currentIndex >= screens.length) {
      _currentIndex = 0;
    }

    return MultiBlocListener(
      listeners: [
        BlocListener<AuthBloc, AuthState>(
          listenWhen: (prev, curr) =>
              prev is AuthenticatedState &&
              curr is AuthenticatedState &&
              prev.currentStore.storeId != curr.currentStore.storeId,
          listener: (context, state) {
            context.read<CartBloc>().add(LoadCatalogEvent());
            context.read<OrdersBloc>().add(LoadOrdersEvent());
            try {
              context.read<OwnerBloc>().add(LoadExpensesEvent(refresh: true));
              context.read<OwnerBloc>().add(
                _defaultDashboardEvent(context.read<OutletScopeCubit>().state),
              );
            } catch (_) {}
          },
        ),
        // Switching outlet scope (O5.1's OutletSwitcher) must reload orders
        // for the newly-active scope rather than leave stale rows from the
        // previous one on screen — see O5.3's verify condition. From the
        // local cache only: a scope never synced to this phone goes through
        // the setup screen first (main.dart).
        BlocListener<OutletScopeCubit, OutletScope>(
          listenWhen: (prev, curr) =>
              prev.activeOutletId != curr.activeOutletId ||
              prev.allOutlets != curr.allOutlets,
          listener: (context, state) {
            context.read<OrdersBloc>().add(LoadOrdersEvent());
            context.read<OwnerBloc>().add(_outletRollupsEvent(state));
          },
        ),
      ],
      child: Scaffold(
        backgroundColor: AppColors.surface,
        body: notice == null
            ? IndexedStack(index: _currentIndex, children: screens)
            : Column(
                children: [
                  AccessNoticeStrip(notice: notice),
                  // The strip already covers the status bar, so the screens
                  // below must not pad for it a second time.
                  Expanded(
                    child: MediaQuery.removePadding(
                      context: context,
                      removeTop: true,
                      child: IndexedStack(
                        index: _currentIndex,
                        children: screens,
                      ),
                    ),
                  ),
                ],
              ),
        bottomNavigationBar: isOwner
            ? AppBottomNav(
                currentIndex: _currentIndex,
                onTap: (index) {
                  if (index != _currentIndex) {
                    if (_currentIndex == 0) {
                      _dashboardResetSignal.value++;
                    } else if (_currentIndex == 1) {
                      _ordersResetSignal.value++;
                    }
                    setState(() {
                      _currentIndex = index;
                    });
                    AppAnalytics.screenView(switch (index) {
                      0 => 'dashboard',
                      1 => 'orders',
                      _ => 'more',
                    });
                  }
                  // Reload orders whenever the user switches to the Orders
                  // tab so offline-placed orders appear immediately.
                  const ordersTabIndex = 1;
                  if (index == ordersTabIndex) {
                    context.read<OrdersBloc>().add(LoadOrdersEvent());
                  }
                  const moreTabIndex = 2;
                  if (index == moreTabIndex) {
                    try {
                      context.read<OwnerBloc>().add(
                        LoadExpensesEvent(refresh: true),
                      );
                    } catch (_) {}
                  }
                },
              )
            : null,
      ),
    );
  }
}
