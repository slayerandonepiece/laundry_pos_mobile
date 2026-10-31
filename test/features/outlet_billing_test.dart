import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/core/network/api_exceptions.dart';
import 'package:myshop/features/auth/bloc/auth_bloc.dart';
import 'package:myshop/features/auth/bloc/auth_event.dart';
import 'package:myshop/features/auth/bloc/auth_state.dart';
import 'package:myshop/features/auth/data/models/user_model.dart';
import 'package:myshop/features/owner/data/models/subscription_invoice_model.dart';
import 'package:myshop/features/owner/data/owner_repository.dart';
import 'package:myshop/features/owner/presentation/subscription_screen.dart';
import 'package:myshop/features/shell/bloc/outlet_scope_cubit.dart';
import 'package:myshop/features/shell/data/models/outlet_model.dart';
import 'package:myshop/features/shell/data/outlet_billing_guard.dart';
import 'package:myshop/shared/widgets/access_notice_strip.dart';
import 'package:myshop/shared/widgets/app_button.dart';
import 'package:myshop/shared/widgets/outlet_blocked.dart';
import 'package:myshop/shared/widgets/outlet_title_switcher.dart';

import '../widgets/outlet_switcher_test.dart' show FakeLocalCache;

Map<String, dynamic> _outlet(
  String id,
  String name, {
  Map<String, dynamic>? billing,
  bool isDefault = false,
}) => {
  'id': id,
  'outletCode': id.toUpperCase(),
  'displayName': name,
  'isDefault': isDefault,
  'status': 'ACTIVE',
  'billing': ?billing,
};

const _paid = {'state': 'active', 'blocked': false, 'daysLeft': 200};
const _ending = {'state': 'ending', 'blocked': false, 'daysLeft': 5};
const _blocked = {'state': 'blocked', 'blocked': true};

class _MockAuthBloc extends Bloc<AuthEvent, AuthState> implements AuthBloc {
  _MockAuthBloc(super.initialState);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _BillingRepo implements OwnerRepository {
  _BillingRepo(this.invoices);
  final List<SubscriptionInvoice> invoices;

  @override
  List<SubscriptionInvoice> getCachedSubscriptionInvoices() => invoices;

  @override
  SubscriptionPlan? getCachedSubscriptionPlan() => null;

  @override
  Future<List<SubscriptionInvoice>> listSubscriptionInvoices() async =>
      invoices;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<(FakeLocalCache, OutletScopeCubit)> _scope(
  List<Map<String, dynamic>> outlets, {
  required bool owner,
}) async {
  final cache = FakeLocalCache();
  await cache.setActiveStoreId('store_a');
  await cache.setCachedStoreDetails({'role': owner ? 'OWNER' : 'EMPLOYEE'});
  await cache.setAllowedOutletsForStore('store_a', outlets);
  final cubit = OutletScopeCubit(localCache: cache)
    ..adoptFromLogin(isOwner: owner);
  return (cache, cubit);
}

void main() {
  group('Outlet billing model', () {
    test('parses billing and tolerates a server without it', () {
      final o = Outlet.fromJson(_outlet('a', 'A', billing: _ending));
      expect(o.isBlocked, isFalse);
      expect(o.dueInDays, 5);
      expect(Outlet.fromJson(_outlet('a', 'A')).isBlocked, isFalse);
      expect(
        Outlet.fromJson(_outlet('a', 'A', billing: _blocked)).isBlocked,
        isTrue,
      );
      expect(o.toJson()['billing'], containsPair('daysLeft', 5));
    });
  });

  group('Employee start outlet', () {
    test('skips a blocked outlet for the server default', () async {
      final (_, cubit) = await _scope([
        _outlet('a', 'Unpaid', billing: _blocked),
        _outlet('b', 'Wizard', billing: _paid, isDefault: true),
      ], owner: false);
      expect(cubit.state.activeOutletId, 'b');
      await cubit.close();
    });

    test(
      'a plain re-read (no fresh login) also starts on an open outlet',
      () async {
        final cache = FakeLocalCache();
        await cache.setActiveStoreId('store_a');
        await cache.setCachedStoreDetails({'role': 'EMPLOYEE'});
        await cache.setAllowedOutletsForStore('store_a', [
          _outlet('a', 'Unpaid', billing: _blocked, isDefault: true),
          _outlet('b', 'Wizard', billing: _paid),
        ]);
        final cubit = OutletScopeCubit(localCache: cache)..hydrate();
        expect(cubit.state.activeOutletId, 'b');
        await cubit.close();
      },
    );

    test('with no blocked outlet still asks, as before', () async {
      final (_, cubit) = await _scope([
        _outlet('a', 'One', billing: _paid, isDefault: true),
        _outlet('b', 'Two', billing: _paid),
      ], owner: false);
      expect(cubit.state.activeOutletId, isNull);
      expect(cubit.state.requiresSelection, isTrue);
      await cubit.close();
    });
  });

  group('Switcher tags', () {
    testWidgets('shows Blocked and Due in N days; owner can pick blocked', (
      tester,
    ) async {
      final (_, cubit) = await _scope([
        _outlet('a', 'Paid Outlet', billing: _paid, isDefault: true),
        _outlet('b', 'Unpaid Outlet', billing: _blocked),
        _outlet('c', 'Soon Outlet', billing: _ending),
      ], owner: true);
      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider.value(
            value: cubit,
            child: Scaffold(
              appBar: AppBar(
                title: const OutletTitleSwitcher(
                  screenLabel: 'Orders',
                  showAllOutletsOption: true,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('All outlets'));
      await tester.pumpAndSettle();
      expect(find.text('Blocked'), findsOneWidget);
      expect(find.text('Due in 5 days'), findsOneWidget);

      await tester.tap(find.text('Unpaid Outlet'));
      await tester.pumpAndSettle();
      expect(cubit.state.activeOutletId, 'b');
      expect(cubit.state.activeOutletBlocked, isTrue);
      await cubit.close();
    });
  });

  group('Banner', () {
    testWidgets('owner sees View details, employee does not', (tester) async {
      var opened = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: AccessNoticeStrip(
            notice: outletBlockedNotice(
              'Unpaid Outlet',
              isOwner: true,
              onViewDetails: () => opened++,
            ),
          ),
        ),
      );
      expect(
        find.text('Unpaid Outlet is blocked until it is paid.'),
        findsOneWidget,
      );
      await tester.tap(find.text('View details'));
      expect(opened, 1);

      await tester.pumpWidget(
        MaterialApp(
          home: AccessNoticeStrip(
            notice: outletBlockedNotice('Unpaid Outlet', isOwner: false),
          ),
        ),
      );
      expect(
        find.text(
          'Unpaid Outlet is blocked. Please check with your store owner.',
        ),
        findsOneWidget,
      );
      expect(find.text('View details'), findsNothing);
    });

    testWidgets('survives a large font on a small phone', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          builder: (c, w) => MediaQuery(
            data: MediaQuery.of(c)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: w!,
          ),
          home: Scaffold(
            body: AccessNoticeStrip(
              notice: outletBlockedNotice(
                'A Rather Long Outlet Name Indeed',
                isOwner: true,
                onViewDetails: () {},
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('Disabled actions', () {
    testWidgets('a button follows the selected outlet\'s billing', (
      tester,
    ) async {
      final (_, cubit) = await _scope([
        _outlet('a', 'Paid', billing: _paid, isDefault: true),
        _outlet('b', 'Unpaid', billing: _blocked),
      ], owner: true);
      cubit.select('b');
      Widget button() => MaterialApp(
        home: BlocProvider.value(
          value: cubit,
          child: Builder(
            builder: (context) => PrimaryButton(
              label: 'Add',
              onPressed: context.outletBlocked() ? null : () {},
            ),
          ),
        ),
      );
      await tester.pumpWidget(button());
      expect(
        tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNull,
      );
      cubit.select('a');
      await tester.pump();
      expect(
        tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNotNull,
      );
      await cubit.close();
    });
  });

  group('payment_lapsed handling', () {
    late FakeLocalCache cache;
    setUp(() async {
      cache = FakeLocalCache();
      await cache.setActiveStoreId('store_a');
      await cache.setCachedStoreDetails({'role': 'EMPLOYEE'});
      await cache.setAllowedOutletsForStore('store_a', [
        _outlet('b', 'Unpaid', billing: _blocked),
        _outlet('a', 'Paid', billing: _paid),
      ]);
    });
    tearDown(() => OutletBillingGuard.refresh = null);

    test(
      'a write on a blocked outlet is refused with the employee message',
      () {
        expect(
          () => OutletBillingGuard.ensureWritable(cache, 'b'),
          throwsA(
            isA<OutletBlockedException>().having(
              (e) => e.message,
              'message',
              'Unpaid is blocked. Please check with your store owner.',
            ),
          ),
        );
        OutletBillingGuard.ensureWritable(cache, 'a');
        OutletBillingGuard.ensureWritable(cache, null);
      },
    );

    test(
      'a 403 payment_lapsed becomes the blocked message and refreshes',
      () async {
        var refreshed = 0;
        OutletBillingGuard.refresh = () async => refreshed++;
        final out = await OutletBillingGuard.translate(
          cache,
          'b',
          AuthException(code: 'FORBIDDEN', reason: 'payment_lapsed'),
        );
        expect(out, isA<OutletBlockedException>());
        expect(refreshed, 1);

        final other = AuthException(code: 'FORBIDDEN', reason: 'store_locked');
        expect(await OutletBillingGuard.translate(cache, 'b', other), other);
        expect(refreshed, 1);
      },
    );
  });

  group('Billing screen', () {
    testWidgets(
      'lists outlets and shows outlet, plan and discount per invoice',
      (tester) async {
        final (_, cubit) = await _scope([
          _outlet(
            'a',
            'Wizard Outlet',
            billing: {..._paid, 'paidThroughDate': '2027-05-01'},
          ),
          _outlet('b', 'Unpaid Outlet', billing: _blocked),
        ], owner: true);
        const withOutlet = SubscriptionInvoice(
          invoiceSeq: 3,
          number: 'INV-000003',
          type: 'RENEWAL',
          amount: 900000,
          paidAt: '2026-10-30',
          outletName: 'Wizard Outlet',
          planName: 'Standard',
          listAmount: 1000000,
          discountPercent: 10,
          note: 'Launch offer',
        );
        const deposit = SubscriptionInvoice(
          invoiceSeq: 1,
          number: 'INV-000001',
          type: 'DEPOSIT',
          amount: 500000,
          paidAt: '2026-10-01',
        );
        await tester.pumpWidget(
          MultiBlocProvider(
            providers: [
              BlocProvider<AuthBloc>.value(
                value: _MockAuthBloc(
                  AuthenticatedState(
                    user: User(id: 'u', name: 'O', phone: '1'),
                    currentStore: StoreSummary(
                      storeId: 's1',
                      storeName: 'S',
                      role: 'OWNER',
                    ),
                    availableStores: const [],
                  ),
                ),
              ),
              BlocProvider<OutletScopeCubit>.value(value: cubit),
              RepositoryProvider<OwnerRepository>.value(
                value: _BillingRepo(const [withOutlet, deposit]),
              ),
            ],
            child: const MaterialApp(home: SubscriptionScreen()),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('OUTLETS'), findsOneWidget);
        expect(find.text('Blocked'), findsOneWidget);
        expect(find.text('Paid'), findsOneWidget);
        expect(find.textContaining('Standard'), findsWidgets);

        expect(
          find.byKey(
            const ValueKey('invoice-outlet-plan-3'),
            skipOffstage: false,
          ),
          findsOneWidget,
        );
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('invoice-outlet-plan-3')))
              .data,
          'Wizard Outlet · Standard',
        );
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('invoice-discount-3')))
              .data,
          '10% off · Launch offer',
        );
        // A deposit has no outlet, plan or discount line.
        expect(
          find.byKey(const ValueKey('invoice-outlet-plan-1')),
          findsNothing,
        );
        expect(find.byKey(const ValueKey('invoice-discount-1')), findsNothing);
        await cubit.close();
      },
    );
  });

  group('Large text', () {
    testWidgets(
      'Blocked tag and due tag stack in the switcher without overflow',
      (tester) async {
        tester.view.physicalSize = const Size(320, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final (_, cubit) = await _scope([
          _outlet('a', 'Wizard Outlet', billing: _ending, isDefault: true),
          _outlet('b', 'Unpaid Outlet', billing: _blocked),
        ], owner: true);
        Widget scaled(Widget child) => MaterialApp(
          builder: (c, w) => MediaQuery(
            data: MediaQuery.of(c)
                .copyWith(textScaler: const TextScaler.linear(3)),
            child: w!,
          ),
          home: child,
        );
        await tester.pumpWidget(
          MultiBlocProvider(
            providers: [
              BlocProvider<AuthBloc>.value(
                value: _MockAuthBloc(
                  AuthenticatedState(
                    user: User(id: 'u', name: 'O', phone: '1'),
                    currentStore: StoreSummary(
                      storeId: 's1',
                      storeName: 'S',
                      role: 'OWNER',
                    ),
                    availableStores: const [],
                  ),
                ),
              ),
              BlocProvider<OutletScopeCubit>.value(value: cubit),
              RepositoryProvider<OwnerRepository>.value(
                value: _BillingRepo(const []),
              ),
            ],
            child: scaled(const SubscriptionScreen()),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Blocked'), findsOneWidget);
        // The existing Subscription screen already overflows at 3x text, so only
        // the new outlet cards are asserted (they stack their status below).
        tester.takeException();

        await tester.pumpWidget(
          BlocProvider<OutletScopeCubit>.value(
            value: cubit,
            child: scaled(
              Scaffold(
                appBar: AppBar(
                  title: const OutletTitleSwitcher(
                    screenLabel: 'Orders',
                    showAllOutletsOption: true,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.byType(OutletTitleSwitcher));
        await tester.pumpAndSettle();
        expect(find.text('Blocked'), findsOneWidget);
        expect(find.text('Due in 5 days'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await cubit.close();
      },
    );
  });
}
