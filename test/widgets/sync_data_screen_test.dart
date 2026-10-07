import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:myshop/core/storage/local_cache.dart';
import 'package:myshop/features/auth/bloc/auth_bloc.dart';
import 'package:myshop/features/auth/bloc/auth_event.dart';
import 'package:myshop/features/auth/bloc/auth_state.dart';
import 'package:myshop/features/auth/data/auth_repository.dart';
import 'package:myshop/features/auth/data/models/user_model.dart';
import 'package:myshop/features/orders/data/orders_repository.dart';
import 'package:myshop/features/owner/data/owner_repository.dart';
import 'package:myshop/features/pos/data/pos_repository.dart';
import 'package:myshop/features/profile/presentation/sync_data_screen.dart';

class _Orders implements OrdersRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Pos implements PosRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Owner implements OwnerRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Auth implements AuthRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _AuthBloc extends Bloc<AuthEvent, AuthState> implements AuthBloc {
  _AuthBloc(super.initial);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('sync_data_screen');
    Hive.init(dir.path);
    await Hive.openBox(LocalCacheService.boxName);
  });

  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  Widget app(String role) => MultiRepositoryProvider(
    providers: [
      RepositoryProvider<OrdersRepository>.value(value: _Orders()),
      RepositoryProvider<PosRepository>.value(value: _Pos()),
      RepositoryProvider<OwnerRepository>.value(value: _Owner()),
      RepositoryProvider<AuthRepository>.value(value: _Auth()),
    ],
    child: BlocProvider<AuthBloc>.value(
      value: _AuthBloc(
        AuthenticatedState(
          user: User(id: 'u', phone: 'p', name: 'n'),
          currentStore: StoreSummary(
            storeId: 's',
            storeName: 'Shop',
            role: role,
          ),
          availableStores: const [],
        ),
      ),
      child: const MaterialApp(home: SyncDataScreen()),
    ),
  );

  testWidgets('owner sees every dataset and the templates note', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app('OWNER'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    for (final name in [
      'Sync everything',
      'Status',
      'Profile',
      'Services and prices',
      'Payment methods',
      'Orders',
      'Expenses',
      'Employees',
      'Invoices',
      'Message templates',
    ]) {
      expect(find.text(name), findsOneWidget, reason: name);
    }
  });

  testWidgets('an employee does not see owner-only datasets', (tester) async {
    tester.view.physicalSize = const Size(800, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app('EMPLOYEE'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Services and prices'), findsOneWidget);
    for (final name in ['Expenses', 'Employees', 'Invoices']) {
      expect(find.text(name), findsNothing, reason: name);
    }
  });

  testWidgets('says so when nothing has been synced yet', (tester) async {
    tester.view.physicalSize = const Size(800, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app('OWNER'));
    await tester.pump();
    expect(find.text('Some data has not been synced yet.'), findsOneWidget);
  });

  testWidgets('shows how long ago the oldest sync was', (tester) async {
    tester.view.physicalSize = const Size(800, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final cache = LocalCacheService();
    // Hive writes are real I/O, so they run outside the test's fake clock.
    await tester.runAsync(() async {
      await cache.setActiveStoreId('s');
      for (final name in [
        'Status',
        'Profile',
        'Services and prices',
        'Payment methods',
        'Orders::none',
        'Message templates',
        'Expenses',
        'Employees',
        'Invoices',
      ]) {
        await cache.setSyncedAt(name);
      }
    });
    await tester.pumpWidget(app('OWNER'));
    await tester.pump();
    expect(find.text('Last synced just now.'), findsOneWidget);
  });
}
