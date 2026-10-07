import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/features/auth/bloc/auth_bloc.dart';
import 'package:myshop/features/auth/bloc/auth_event.dart';
import 'package:myshop/features/auth/bloc/auth_state.dart';
import 'package:myshop/features/auth/data/models/user_model.dart';
import 'package:myshop/features/owner/bloc/owner_bloc.dart';
import 'package:myshop/features/owner/data/models/dashboard_model.dart';
import 'package:myshop/features/owner/data/models/subscription_invoice_model.dart';
import 'package:myshop/features/owner/data/owner_repository.dart';
import 'package:myshop/features/owner/presentation/more_screen.dart';
import 'package:myshop/features/owner/presentation/subscription_invoice_viewer_screen.dart';
import 'package:myshop/features/owner/presentation/subscription_screen.dart';

class MockAuthBloc extends Bloc<AuthEvent, AuthState> implements AuthBloc {
  MockAuthBloc(super.initialState);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeOwnerRepository implements OwnerRepository {
  @override
  Future<DashboardMetrics> getDashboardMetrics({
    String? from,
    String? to,
    String? granularity,
  }) async => DashboardMetrics();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeBillingRepository implements OwnerRepository {
  List<SubscriptionInvoice> cached = const [];
  List<SubscriptionInvoice> remote = const [];
  bool failList = false;
  SubscriptionPlan? plan;
  int pdfAsked = 0;

  @override
  List<SubscriptionInvoice> getCachedSubscriptionInvoices() => cached;

  @override
  SubscriptionPlan? getCachedSubscriptionPlan() => plan;

  @override
  Future<List<SubscriptionInvoice>> listSubscriptionInvoices() async {
    if (failList) throw Exception('offline');
    return remote;
  }

  @override
  Future<Uint8List> getSubscriptionInvoicePdf(int invoiceSeq) {
    pdfAsked = invoiceSeq;
    return Completer<Uint8List>().future; // never answers: spinner stays
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _renewal = SubscriptionInvoice(
  invoiceSeq: 2,
  number: 'INV-000002',
  type: 'RENEWAL',
  amount: 1200000,
  method: 'CASH',
  paidAt: '2026-09-25',
  coversFrom: '2026-09-25',
  coversTo: '2027-09-24',
);
const _deposit = SubscriptionInvoice(
  invoiceSeq: 1,
  number: 'INV-000001',
  type: 'DEPOSIT',
  amount: 500000,
  method: 'UPI',
  paidAt: '2026-09-20',
);

AuthState createAuthState({
  String? paidThroughDate,
  String? trialEndsAt,
  String? subscriptionState,
}) {
  return AuthenticatedState(
    user: User(id: 'u1', name: 'Alice Owner', phone: 'alice'),
    currentStore: StoreSummary(
      storeId: 's1',
      storeName: 'MyShop',
      role: 'OWNER',
      paidThroughDate: paidThroughDate,
      trialEndsAt: trialEndsAt,
      subscriptionState: subscriptionState,
    ),
    availableStores: [
      StoreSummary(
        storeId: 's1',
        storeName: 'MyShop',
        role: 'OWNER',
        paidThroughDate: paidThroughDate,
        trialEndsAt: trialEndsAt,
        subscriptionState: subscriptionState,
      ),
    ],
  );
}

void main() {
  group('SubscriptionScreen Tests', () {
    testWidgets(
      '1. Active-plan state renders correctly when paidThroughDate is a future date (> 7 days)',
      (tester) async {
        final futureDate = DateTime.now().add(const Duration(days: 30));
        final dateStr =
            '${futureDate.year}-${futureDate.month.toString().padLeft(2, '0')}-${futureDate.day.toString().padLeft(2, '0')}';

        final authBloc = MockAuthBloc(
          createAuthState(paidThroughDate: dateStr),
        );

        await tester.pumpWidget(
          BlocProvider<AuthBloc>.value(
            value: authBloc,
            child: const MaterialApp(home: SubscriptionScreen()),
          ),
        );

        expect(find.text('Subscription'), findsOneWidget);
        expect(find.text('Your plan is active'), findsOneWidget);
        expect(find.text('Renews on $dateStr'), findsOneWidget);

        // No repository (or no payments yet): an honest empty state.
        expect(find.text('INVOICES'), findsOneWidget);
        expect(find.text('No invoices yet'), findsOneWidget);
        expect(find.text('Contact support about billing'), findsOneWidget);
      },
    );

    testWidgets(
      '2. Renewal-warning state renders when paidThroughDate is near (<= 7 days) or in the past',
      (tester) async {
        final nearDate = DateTime.now().add(const Duration(days: 3));
        final dateStr =
            '${nearDate.year}-${nearDate.month.toString().padLeft(2, '0')}-${nearDate.day.toString().padLeft(2, '0')}';

        final authBloc = MockAuthBloc(
          createAuthState(paidThroughDate: dateStr),
        );

        await tester.pumpWidget(
          BlocProvider<AuthBloc>.value(
            value: authBloc,
            child: const MaterialApp(home: SubscriptionScreen()),
          ),
        );

        expect(find.text('Your plan renews soon'), findsOneWidget);
        expect(
          find.text('Please keep payment updated. Renews on $dateStr.'),
          findsOneWidget,
        );
        expect(find.text('Your plan is active'), findsNothing);
      },
    );

    testWidgets(
      '3. Null-date neutral state renders when paidThroughDate is null',
      (tester) async {
        final authBloc = MockAuthBloc(createAuthState(paidThroughDate: null));

        await tester.pumpWidget(
          BlocProvider<AuthBloc>.value(
            value: authBloc,
            child: const MaterialApp(home: SubscriptionScreen()),
          ),
        );

        expect(find.text('Plan status unavailable'), findsOneWidget);
        expect(
          find.text("Plan status isn't available right now."),
          findsOneWidget,
        );
        expect(find.text('Your plan is active'), findsNothing);
        expect(find.text('Your plan renews soon'), findsNothing);
      },
    );

    testWidgets(
      '4. TRIAL state renders neutral card with "Trial" and trialEndsAt date',
      (tester) async {
        final authBloc = MockAuthBloc(
          createAuthState(
            subscriptionState: 'TRIAL',
            trialEndsAt: '2026-10-15',
          ),
        );

        await tester.pumpWidget(
          BlocProvider<AuthBloc>.value(
            value: authBloc,
            child: const MaterialApp(home: SubscriptionScreen()),
          ),
        );

        expect(find.text('Trial'), findsOneWidget);
        expect(find.text('Trial ends on 2026-10-15'), findsOneWidget);
        expect(find.text('Your plan is active'), findsNothing);
        expect(find.text('Your plan renews soon'), findsNothing);
      },
    );

    testWidgets(
      '5. TRIAL_ENDING state renders warning card with "Trial ending" and trialEndsAt date',
      (tester) async {
        final authBloc = MockAuthBloc(
          createAuthState(
            subscriptionState: 'TRIAL_ENDING',
            trialEndsAt: '2026-09-30',
            paidThroughDate: '2026-10-30',
          ),
        );

        await tester.pumpWidget(
          BlocProvider<AuthBloc>.value(
            value: authBloc,
            child: const MaterialApp(home: SubscriptionScreen()),
          ),
        );

        expect(find.text('Trial ending'), findsOneWidget);
        expect(
          find.text('Please keep payment updated. Trial ends on 2026-09-30.'),
          findsOneWidget,
        );
        expect(find.text('Your plan is active'), findsNothing);
      },
    );

    testWidgets(
      '6. SUBSCRIPTION_ENDING state renders warning card with "Your plan renews soon" and paidThroughDate',
      (tester) async {
        final authBloc = MockAuthBloc(
          createAuthState(
            subscriptionState: 'SUBSCRIPTION_ENDING',
            paidThroughDate: '2026-10-02',
          ),
        );

        await tester.pumpWidget(
          BlocProvider<AuthBloc>.value(
            value: authBloc,
            child: const MaterialApp(home: SubscriptionScreen()),
          ),
        );

        expect(find.text('Your plan renews soon'), findsOneWidget);
        expect(
          find.text('Please keep payment updated. Renews on 2026-10-02.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      '7. ACTIVE state with future date (> 7 days) renders "Your plan is active"',
      (tester) async {
        final futureDate = DateTime.now().add(const Duration(days: 25));
        final dateStr =
            '${futureDate.year}-${futureDate.month.toString().padLeft(2, '0')}-${futureDate.day.toString().padLeft(2, '0')}';

        final authBloc = MockAuthBloc(
          createAuthState(
            subscriptionState: 'ACTIVE',
            paidThroughDate: dateStr,
          ),
        );

        await tester.pumpWidget(
          BlocProvider<AuthBloc>.value(
            value: authBloc,
            child: const MaterialApp(home: SubscriptionScreen()),
          ),
        );

        expect(find.text('Your plan is active'), findsOneWidget);
        expect(find.text('Renews on $dateStr'), findsOneWidget);
      },
    );

    testWidgets(
      '8. Tapping "Subscription" in MoreScreen navigates to SubscriptionScreen',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final futureDate = DateTime.now().add(const Duration(days: 30));
        final dateStr =
            '${futureDate.year}-${futureDate.month.toString().padLeft(2, '0')}-${futureDate.day.toString().padLeft(2, '0')}';

        final authBloc = MockAuthBloc(
          createAuthState(paidThroughDate: dateStr),
        );
        final ownerBloc = OwnerBloc(ownerRepository: FakeOwnerRepository());

        await tester.pumpWidget(
          MultiBlocProvider(
            providers: [
              BlocProvider<AuthBloc>.value(value: authBloc),
              BlocProvider<OwnerBloc>.value(value: ownerBloc),
            ],
            child: const MaterialApp(home: MoreScreen()),
          ),
        );

        expect(find.text('Subscription'), findsOneWidget);

        await tester.tap(find.text('Subscription'));
        await tester.pumpAndSettle();

        expect(find.byType(SubscriptionScreen), findsOneWidget);
        expect(find.text('Your plan is active'), findsOneWidget);
      },
    );

    Widget billingApp(FakeBillingRepository repo) => MultiRepositoryProvider(
      providers: [RepositoryProvider<OwnerRepository>.value(value: repo)],
      child: BlocProvider<AuthBloc>.value(
        value: MockAuthBloc(createAuthState(paidThroughDate: '2100-01-01')),
        child: const MaterialApp(home: SubscriptionScreen()),
      ),
    );

    testWidgets('Shows every subscription invoice with its amount and dates', (
      tester,
    ) async {
      final repo = FakeBillingRepository()..remote = [_renewal, _deposit];
      await tester.pumpWidget(billingApp(repo));
      await tester.pumpAndSettle();

      expect(find.text('2 invoices · ₹17,000 paid in total'), findsOneWidget);
      expect(find.text('Annual renewal'), findsOneWidget);
      expect(find.text('Subscription deposit'), findsOneWidget);
      expect(find.text('₹12,000'), findsOneWidget);
      expect(find.text('INV-000002'), findsOneWidget);
      expect(find.text('Paid 25 Sep 2026 · Cash'), findsOneWidget);
      expect(find.text('Covers 25 Sep 2026 – 24 Sep 2027'), findsOneWidget);
      expect(find.text('Paid 20 Sep 2026 · UPI'), findsOneWidget);
    });

    testWidgets('Shows the current term from the invoice that ends last', (
      tester,
    ) async {
      final repo = FakeBillingRepository()..remote = [_deposit, _renewal];
      await tester.pumpWidget(billingApp(repo));
      await tester.pumpAndSettle();

      expect(find.text('CURRENT TERM'), findsOneWidget);
      expect(find.text('to 24 Sep 2027'), findsOneWidget);
      expect(find.text('PAID THROUGH'), findsOneWidget);
      expect(find.text('1 Jan 2100'), findsOneWidget);
    });

    testWidgets('No paid invoice yet: says there is no paid term', (
      tester,
    ) async {
      final repo = FakeBillingRepository()..remote = [_deposit];
      await tester.pumpWidget(billingApp(repo));
      await tester.pumpAndSettle();

      expect(find.text('No paid term yet'), findsOneWidget);
    });

    testWidgets(
      'Shows the plan, fees and renewal fee when the server sends them',
      (tester) async {
        final repo = FakeBillingRepository()
          ..remote = [_renewal]
          ..plan = const SubscriptionPlan(
            planName: 'Standard',
            annualFeeAmount: 500000,
            depositAmount: 1000000,
          );
        await tester.pumpWidget(billingApp(repo));
        await tester.pumpAndSettle();

        expect(find.text('PLAN'), findsOneWidget);
        expect(find.text('Standard'), findsOneWidget);
        expect(
          find.text('Annual fee ₹5,000 · Deposit ₹10,000'),
          findsOneWidget,
        );
        expect(find.text('Renewal fee ₹5,000'), findsOneWidget);
      },
    );

    testWidgets('Custom terms: no plan name, no deposit line', (tester) async {
      final repo = FakeBillingRepository()
        ..remote = [_renewal]
        ..plan = const SubscriptionPlan(
          annualFeeAmount: 500000,
          depositAmount: 0,
        );
      await tester.pumpWidget(billingApp(repo));
      await tester.pumpAndSettle();

      expect(find.text('Custom terms'), findsOneWidget);
      expect(find.text('Annual fee ₹5,000'), findsOneWidget);
    });

    testWidgets('A failed refresh keeps showing what the phone already has', (
      tester,
    ) async {
      final repo = FakeBillingRepository()
        ..cached = [_renewal]
        ..failList = true;
      await tester.pumpWidget(billingApp(repo));
      await tester.pumpAndSettle();

      expect(find.text('Annual renewal'), findsOneWidget);
      expect(
        find.text("Showing what's saved on this phone. Couldn't refresh."),
        findsOneWidget,
      );
    });

    testWidgets('Nothing saved and the request fails: says so, with retry', (
      tester,
    ) async {
      final repo = FakeBillingRepository()..failList = true;
      await tester.pumpWidget(billingApp(repo));
      await tester.pumpAndSettle();

      expect(find.text("Couldn't load your invoices"), findsOneWidget);
      repo.failList = false;
      repo.remote = [_deposit];
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Subscription deposit'), findsOneWidget);
    });

    testWidgets('Tapping an invoice opens it and asks the server for its PDF', (
      tester,
    ) async {
      final repo = FakeBillingRepository()..remote = [_renewal];
      await tester.pumpWidget(billingApp(repo));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('subscription-invoice-2')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(repo.pdfAsked, 2);
      expect(find.byType(SubscriptionInvoiceViewerScreen), findsOneWidget);
      expect(find.byTooltip('Share'), findsOneWidget);
    });
  });
}
