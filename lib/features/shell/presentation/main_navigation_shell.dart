import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:myshop/core/constants/app_colors.dart';
import 'package:myshop/features/auth/bloc/auth_bloc.dart';
import 'package:myshop/features/auth/bloc/auth_state.dart';
import 'package:myshop/features/orders/bloc/orders_bloc.dart';
import 'package:myshop/features/orders/bloc/orders_event.dart';
import 'package:myshop/features/orders/presentation/orders_list_screen.dart';
import 'package:myshop/features/owner/presentation/more_screen.dart';
import 'package:myshop/features/owner/presentation/owner_dashboard_screen.dart';
import 'package:myshop/features/pos/bloc/cart_bloc.dart';
import 'package:myshop/features/pos/bloc/cart_event.dart';
import 'package:myshop/shared/widgets/bottom_nav.dart';

class MainNavigationShell extends StatefulWidget {
  const MainNavigationShell({super.key});

  @override
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthBloc>().state;
    final isOwner = authState is AuthenticatedState && authState.isOwner;

    // Orders now has its own "start new order" FAB, so New Sale is no
    // longer a separate screen at all.
    // Employee: [OrdersListScreen] — the only screen, no bottom bar needed.
    // Owner: [OwnerDashboardScreen, OrdersListScreen, MoreScreen]
    final List<Widget> screens = isOwner
        ? [
            OwnerDashboardScreen(
              onOrdersTabPressed: () => setState(() => _currentIndex = 1),
            ),
            const OrdersListScreen(),
            const MoreScreen(),
          ]
        : [const OrdersListScreen()];

    // Safety check if index exceeds screens length after role switch
    if (_currentIndex >= screens.length) {
      _currentIndex = 0;
    }

    return BlocListener<AuthBloc, AuthState>(
      listenWhen: (prev, curr) =>
          prev is AuthenticatedState &&
          curr is AuthenticatedState &&
          prev.currentStore.storeId != curr.currentStore.storeId,
      listener: (context, state) {
        context.read<CartBloc>().add(LoadCatalogEvent());
        context.read<OrdersBloc>().add(LoadOrdersEvent());
      },
      child: Scaffold(
        backgroundColor: AppColors.surface,
        body: IndexedStack(index: _currentIndex, children: screens),
        bottomNavigationBar: isOwner
            ? AppBottomNav(
                currentIndex: _currentIndex,
                onTap: (index) {
                  setState(() {
                    _currentIndex = index;
                  });
                  // Reload orders whenever the user switches to the Orders
                  // tab so offline-placed orders appear immediately.
                  const ordersTabIndex = 1;
                  if (index == ordersTabIndex) {
                    context.read<OrdersBloc>().add(LoadOrdersEvent());
                  }
                },
              )
            : null,
      ),
    );
  }
}
