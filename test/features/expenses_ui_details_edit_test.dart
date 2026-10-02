import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/core/storage/local_cache.dart';
import 'package:myshop/core/sync/connectivity_service.dart';
import 'package:myshop/core/utils/currency_formatter.dart';
import 'package:myshop/core/utils/date_formatter.dart';
import 'package:myshop/features/owner/bloc/owner_bloc.dart';
import 'package:myshop/features/owner/bloc/owner_event.dart';
import 'package:myshop/features/owner/bloc/owner_state.dart';
import 'package:myshop/features/owner/data/models/expense_model.dart';
import 'package:myshop/features/owner/presentation/expenses_screen.dart';
import 'package:myshop/features/shell/bloc/outlet_scope_cubit.dart';
import 'package:myshop/shared/widgets/app_button.dart';
import 'package:myshop/shared/widgets/centred_dialog.dart';
import 'package:myshop/shared/widgets/money_text.dart';

class _MockConnectivityService extends ConnectivityService {
  _MockConnectivityService({this.mockOffline = false}) : super.internal();
  bool mockOffline;

  @override
  bool get isOffline => mockOffline;

  @override
  Future<bool> checkIsOffline() async => mockOffline;
}

class _TrackingOwnerBloc extends Bloc<OwnerEvent, OwnerState>
    implements OwnerBloc {
  final List<OwnerEvent> dispatchedEvents = [];

  _TrackingOwnerBloc([OwnerState? initial])
    : super(initial ?? OwnerState(expenses: const [])) {
    on<OwnerEvent>((event, emit) {
      dispatchedEvents.add(event);
    });
  }

  void push(OwnerState next) => emit(next);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeLocalCache extends LocalCacheService {
  final List<Map<String, dynamic>> allowedOutlets;
  String? activeOutletId;
  bool allOutletsScope = true;

  _FakeLocalCache({required this.allowedOutlets});

  @override
  Map<String, dynamic>? getCachedUser() => null;

  @override
  Map<String, dynamic>? getCachedStoreDetails() => const {'role': 'OWNER'};

  @override
  List<Map<String, dynamic>>? getAllowedOutlets() => allowedOutlets;

  @override
  String? getActiveOutletId() => activeOutletId;

  @override
  Future<void> setActiveOutletId(String outletId) async {
    activeOutletId = outletId;
  }

  @override
  Future<void> clearActiveOutletId() async {
    activeOutletId = null;
  }

  @override
  bool isAllOutletsScope() => allOutletsScope;

  @override
  Future<void> setAllOutletsScope(bool allOutlets) async {
    allOutletsScope = allOutlets;
  }

  @override
  Future<void> clearAllOutletsScope() async {
    allOutletsScope = false;
  }

  @override
  bool hasCachedOrdersFor({String? outletId, required bool allOutlets}) => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockConnectivityService mockConnectivity;

  final sampleOutlets = [
    {
      'id': 'o1',
      'outletCode': 'O01',
      'displayName': 'Indiranagar',
      'isDefault': true,
      'status': 'ACTIVE',
    },
    {
      'id': 'o2',
      'outletCode': 'O02',
      'displayName': 'Koramangala',
      'isDefault': false,
      'status': 'ACTIVE',
    },
  ];

  setUp(() {
    mockConnectivity = _MockConnectivityService(mockOffline: false);
    ConnectivityService.instance = mockConnectivity;
  });

  tearDown(() {
    ConnectivityService.instance = ConnectivityService.internal();
  });

  Widget buildWrapper({
    required Widget child,
    required _TrackingOwnerBloc ownerBloc,
    required OutletScopeCubit outletScopeCubit,
  }) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<OwnerBloc>.value(value: ownerBloc),
        BlocProvider<OutletScopeCubit>.value(value: outletScopeCubit),
      ],
      child: MaterialApp(home: child),
    );
  }

  group('M1.5 Expense Details Screen Widget Tests', () {
    testWidgets(
      'renders all fields, MoneyText amount, monthly badge, and attribution',
      (tester) async {
        final cache = _FakeLocalCache(allowedOutlets: sampleOutlets);
        final outletCubit = OutletScopeCubit(localCache: cache)
          ..adoptFromLogin(isOwner: true);
        final ownerBloc = _TrackingOwnerBloc();
        addTearDown(outletCubit.close);
        addTearDown(ownerBloc.close);

        final expense = Expense(
          id: 'exp-det-1',
          title: 'Electricity Bill',
          category: 'Utilities',
          amount: 145000,
          due: '2026-10-15',
          paid: null,
          monthly: true,
          outletId: 'o1',
        );

        await tester.pumpWidget(
          buildWrapper(
            child: ExpenseDetailScreen(expense: expense),
            ownerBloc: ownerBloc,
            outletScopeCubit: outletCubit,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Expense details'), findsOneWidget);
        expect(find.text('Electricity Bill'), findsOneWidget);
        expect(find.byType(MoneyText), findsOneWidget);
        expect(find.text(CurrencyFormatter.format(145000)), findsOneWidget);
        expect(find.text('Utilities'), findsOneWidget);
        expect(find.text('2026-10-15'), findsOneWidget);
        expect(find.text('Unpaid'), findsWidgets);
        expect(find.text('Monthly'), findsOneWidget);
        expect(find.text('Indiranagar'), findsOneWidget);
      },
    );

    testWidgets('organization-wide attribution shown when outletId is null', (
      tester,
    ) async {
      final cache = _FakeLocalCache(allowedOutlets: sampleOutlets);
      final outletCubit = OutletScopeCubit(localCache: cache)
        ..adoptFromLogin(isOwner: true);
      final ownerBloc = _TrackingOwnerBloc();
      addTearDown(outletCubit.close);
      addTearDown(ownerBloc.close);

      final expense = Expense(
        id: 'exp-det-2',
        title: 'Company Cloud Server',
        category: 'Operations',
        amount: 500000,
        due: '2026-10-20',
        paid: '2026-10-01',
        monthly: false,
        outletId: null,
      );

      await tester.pumpWidget(
        buildWrapper(
          child: ExpenseDetailScreen(expense: expense),
          ownerBloc: ownerBloc,
          outletScopeCubit: outletCubit,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Organization-wide'), findsOneWidget);
      expect(find.text('Paid (2026-10-01)'), findsOneWidget);
      expect(find.text('Mark as paid'), findsNothing);
    });

    testWidgets(
      'offline disables Edit and Delete buttons and shows "Needs a connection" text',
      (tester) async {
        mockConnectivity.mockOffline = true;
        final cache = _FakeLocalCache(allowedOutlets: sampleOutlets);
        final outletCubit = OutletScopeCubit(localCache: cache)
          ..adoptFromLogin(isOwner: true);
        final ownerBloc = _TrackingOwnerBloc();
        addTearDown(outletCubit.close);
        addTearDown(ownerBloc.close);

        final expense = Expense(
          id: 'exp-det-3',
          title: 'Floor Cleaner',
          category: 'Supplies',
          amount: 3000,
          due: '2026-10-05',
        );

        await tester.pumpWidget(
          buildWrapper(
            child: ExpenseDetailScreen(expense: expense),
            ownerBloc: ownerBloc,
            outletScopeCubit: outletCubit,
          ),
        );
        await tester.pumpAndSettle();

        // Both buttons exist but are disabled
        final editButton = tester.widget<SecondaryButton>(
          find.widgetWithText(SecondaryButton, 'Edit'),
        );
        final deleteButton = tester.widget<SecondaryButton>(
          find.widgetWithText(SecondaryButton, 'Delete'),
        );

        expect(editButton.onPressed, isNull);
        expect(deleteButton.onPressed, isNull);
        expect(find.text('Needs a connection'), findsOneWidget);
      },
    );

    testWidgets(
      'a bill still syncing (LOCAL- id) disables Edit and Delete even while online',
      (tester) async {
        mockConnectivity.mockOffline = false;
        final cache = _FakeLocalCache(allowedOutlets: sampleOutlets);
        final outletCubit = OutletScopeCubit(localCache: cache)
          ..adoptFromLogin(isOwner: true);
        final ownerBloc = _TrackingOwnerBloc();
        addTearDown(outletCubit.close);
        addTearDown(ownerBloc.close);

        final expense = Expense(
          id: 'LOCAL-1790000000001',
          title: 'Floor Cleaner',
          category: 'Supplies',
          amount: 3000,
          due: '2026-10-05',
        );

        await tester.pumpWidget(
          buildWrapper(
            child: ExpenseDetailScreen(expense: expense),
            ownerBloc: ownerBloc,
            outletScopeCubit: outletCubit,
          ),
        );
        await tester.pumpAndSettle();

        final editButton = tester.widget<SecondaryButton>(
          find.widgetWithText(SecondaryButton, 'Edit'),
        );
        final deleteButton = tester.widget<SecondaryButton>(
          find.widgetWithText(SecondaryButton, 'Delete'),
        );
        expect(editButton.onPressed, isNull);
        expect(deleteButton.onPressed, isNull);
        expect(
          find.text('Still syncing — available once saved'),
          findsOneWidget,
        );
        expect(find.text('Needs a connection'), findsNothing);
      },
    );

    testWidgets(
      'Edit stays open until the server answers: a failure shows its reason, a success closes it',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final cache = _FakeLocalCache(allowedOutlets: sampleOutlets);
        final outletCubit = OutletScopeCubit(localCache: cache)
          ..adoptFromLogin(isOwner: true);
        final ownerBloc = _TrackingOwnerBloc();
        addTearDown(outletCubit.close);
        addTearDown(ownerBloc.close);

        final expense = Expense(
          id: 'exp-edit-2',
          title: 'Store Rent',
          category: 'Rent',
          amount: 600000,
          due: '2026-10-05',
          outletId: 'o1',
        );

        await tester.pumpWidget(
          buildWrapper(
            child: Scaffold(
              body: Builder(
                builder: (ctx) => TextButton(
                  onPressed: () => Navigator.push(
                    ctx,
                    MaterialPageRoute(
                      builder: (_) => EditExpenseScreen(expense: expense),
                    ),
                  ),
                  child: const Text('open edit'),
                ),
              ),
            ),
            ownerBloc: ownerBloc,
            outletScopeCubit: outletCubit,
          ),
        );
        await tester.tap(find.text('open edit'));
        await tester.pumpAndSettle();
        expect(find.text('Edit expense'), findsOneWidget);

        // Save: the event goes out but the screen does not close on its own.
        await tester.tap(find.text('Save expense'));
        await tester.pump();
        expect(ownerBloc.dispatchedEvents.length, 1);
        expect(find.text('Edit expense'), findsOneWidget);

        // The server refuses: the reason shows here and the form stays.
        ownerBloc.push(OwnerState(loading: {OwnerSection.expenses}));
        await tester.pump();
        ownerBloc.push(OwnerState(error: 'This needs a connection'));
        await tester.pump();
        expect(find.text('This needs a connection'), findsOneWidget);
        expect(find.text('Edit expense'), findsOneWidget);

        // Retry succeeds: only now does the screen close.
        await tester.tap(find.text('Save expense'));
        await tester.pump();
        expect(ownerBloc.dispatchedEvents.length, 2);
        ownerBloc.push(OwnerState(loading: {OwnerSection.expenses}));
        await tester.pump();
        ownerBloc.push(OwnerState(expenses: [expense]));
        await tester.pumpAndSettle();
        expect(find.text('Edit expense'), findsNothing);
      },
    );
  });

  group('M1.6 Edit & Delete Flows Widget Tests', () {
    testWidgets(
      'Edit recurring expense: monthly switch disabled, due date clamped to original month',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final cache = _FakeLocalCache(allowedOutlets: sampleOutlets);
        final outletCubit = OutletScopeCubit(localCache: cache)
          ..adoptFromLogin(isOwner: true);
        final ownerBloc = _TrackingOwnerBloc();
        addTearDown(outletCubit.close);
        addTearDown(ownerBloc.close);

        final expense = Expense(
          id: 'exp-edit-1',
          title: 'Store Rent',
          category: 'Rent',
          amount: 6000000, // ₹60,000
          due: '2026-10-05',
          monthly: true,
          outletId: 'o1',
        );

        await tester.pumpWidget(
          buildWrapper(
            child: EditExpenseScreen(expense: expense),
            ownerBloc: ownerBloc,
            outletScopeCubit: outletCubit,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Edit expense'), findsOneWidget);

        // Monthly switch is disabled (onChanged is null)
        final monthlySwitch = tester.widget<Switch>(find.byType(Switch));
        expect(monthlySwitch.value, isTrue);
        expect(monthlySwitch.onChanged, isNull);

        // Tap due date picker
        await tester.tap(find.text('2026-10-05'));
        await tester.pumpAndSettle();

        // DatePickerDialog opens
        final datePicker = tester.widget<DatePickerDialog>(
          find.byType(DatePickerDialog),
        );
        // Clamped to 2026-10
        expect(datePicker.firstDate, DateTime(2026, 10, 1));
        expect(datePicker.lastDate, DateTime(2026, 10, 31));

        // Close picker
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        // Save dispatches UpdateExpenseEvent
        await tester.enterText(
          find.widgetWithText(TextField, 'Store Rent'),
          'Store Rent Indiranagar',
        );
        await tester.tap(find.text('Save expense'));
        // The button now spins until the server answers, so don't settle.
        await tester.pump();

        expect(ownerBloc.dispatchedEvents.length, 1);
        final updateEvt =
            ownerBloc.dispatchedEvents.first as UpdateExpenseEvent;
        expect(updateEvt.expenseId, 'exp-edit-1');
        expect(updateEvt.title, 'Store Rent Indiranagar');
        expect(updateEvt.amount, 6000000);
        expect(updateEvt.outletId, 'o1');
      },
    );

    testWidgets(
      'Delete monthly expense contains warning "This also stops future monthly bills for this expense."',
      (tester) async {
        final cache = _FakeLocalCache(allowedOutlets: sampleOutlets);
        final outletCubit = OutletScopeCubit(localCache: cache)
          ..adoptFromLogin(isOwner: true);
        final ownerBloc = _TrackingOwnerBloc();
        addTearDown(outletCubit.close);
        addTearDown(ownerBloc.close);

        final expense = Expense(
          id: 'exp-del-1',
          title: 'Shop Internet',
          category: 'Utilities',
          amount: 250000,
          due: '2026-10-10',
          monthly: true,
        );

        await tester.pumpWidget(
          buildWrapper(
            child: ExpenseDetailScreen(expense: expense),
            ownerBloc: ownerBloc,
            outletScopeCubit: outletCubit,
          ),
        );
        await tester.pumpAndSettle();

        // Tap Delete button
        await tester.tap(find.widgetWithText(SecondaryButton, 'Delete'));
        await tester.pumpAndSettle();

        // Dialog opened
        expect(find.byType(CentredDialog), findsOneWidget);
        expect(find.text('Delete expense?'), findsOneWidget);
        expect(
          find.textContaining(
            'This also stops future monthly bills for this expense.',
          ),
          findsOneWidget,
        );

        // Confirm delete dispatches DeleteExpenseEvent
        await tester.tap(find.widgetWithText(PrimaryButton, 'Delete'));
        await tester.pumpAndSettle();

        expect(ownerBloc.dispatchedEvents.length, 1);
        final delEvt = ownerBloc.dispatchedEvents.first as DeleteExpenseEvent;
        expect(delEvt.expenseId, 'exp-del-1');
      },
    );
  });

  group('M1.7 Chosen Paid Date Widget Tests', () {
    testWidgets(
      'Mark as paid date picker defaults to today, maxDate is today, minDate is 1 year back',
      (tester) async {
        final cache = _FakeLocalCache(allowedOutlets: sampleOutlets);
        final outletCubit = OutletScopeCubit(localCache: cache)
          ..adoptFromLogin(isOwner: true);
        final ownerBloc = _TrackingOwnerBloc();
        addTearDown(outletCubit.close);
        addTearDown(ownerBloc.close);

        final expense = Expense(
          id: 'exp-pay-picker-1',
          title: 'Water Bill',
          category: 'Utilities',
          amount: 80000,
          due: '2026-10-01',
          paid: null,
        );

        await tester.pumpWidget(
          buildWrapper(
            child: ExpenseDetailScreen(expense: expense),
            ownerBloc: ownerBloc,
            outletScopeCubit: outletCubit,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Mark as paid'));
        await tester.pumpAndSettle();

        final datePicker = tester.widget<DatePickerDialog>(
          find.byType(DatePickerDialog),
        );
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final oneYearAgo = DateTime(today.year - 1, today.month, today.day);

        expect(datePicker.initialDate, today);
        expect(datePicker.lastDate, today);
        expect(datePicker.firstDate, oneYearAgo);

        // Confirming dispatches MarkExpensePaidEvent with today's YYYY-MM-DD
        await tester.tap(find.text('Mark paid'));
        await tester.pumpAndSettle();

        expect(ownerBloc.dispatchedEvents.length, 1);
        final payEvt = ownerBloc.dispatchedEvents.first as MarkExpensePaidEvent;
        expect(payEvt.expenseId, 'exp-pay-picker-1');
        expect(payEvt.paidDate, DateFormatter.todayIsoDateString());
      },
    );

    testWidgets(
      'stays Unpaid after confirming a date until the bloc reports the bill as paid',
      (tester) async {
        final cache = _FakeLocalCache(allowedOutlets: sampleOutlets);
        final outletCubit = OutletScopeCubit(localCache: cache)
          ..adoptFromLogin(isOwner: true);
        final ownerBloc = _TrackingOwnerBloc();
        addTearDown(outletCubit.close);
        addTearDown(ownerBloc.close);

        final expense = Expense(
          id: 'exp-pay-pending-1',
          title: 'Water Bill',
          category: 'Utilities',
          amount: 80000,
          due: '2026-10-01',
        );

        await tester.pumpWidget(
          buildWrapper(
            child: ExpenseDetailScreen(expense: expense),
            ownerBloc: ownerBloc,
            outletScopeCubit: outletCubit,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Mark as paid'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Mark paid'));
        await tester.pumpAndSettle();

        // The event went out, but the server has not confirmed anything yet.
        expect(ownerBloc.dispatchedEvents.single, isA<MarkExpensePaidEvent>());
        expect(find.text('Unpaid'), findsOneWidget);
        expect(find.text('Mark as paid'), findsOneWidget);

        // Success arrives as a refreshed expenses list.
        ownerBloc.push(
          OwnerState(
            expenses: [
              Expense(
                id: expense.id,
                title: expense.title,
                category: expense.category,
                amount: expense.amount,
                due: expense.due,
                paid: '2026-10-01',
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Unpaid'), findsNothing);
        expect(find.text('Paid'), findsOneWidget);
        expect(find.text('Mark as paid'), findsNothing);
      },
    );
  });

  group('M1.8 Outlet Attribution On Create & List Widget Tests', () {
    testWidgets(
      'AddExpenseScreen defaults to currently active outlet and saves with selected outlet',
      (tester) async {
        final cache = _FakeLocalCache(allowedOutlets: sampleOutlets);
        final outletCubit = OutletScopeCubit(localCache: cache)
          ..adoptFromLogin(isOwner: true);
        final ownerBloc = _TrackingOwnerBloc();
        addTearDown(outletCubit.close);
        addTearDown(ownerBloc.close);

        // Select outlet o2 (Koramangala)
        outletCubit.select('o2');

        await tester.pumpWidget(
          buildWrapper(
            child: const AddExpenseScreen(),
            ownerBloc: ownerBloc,
            outletScopeCubit: outletCubit,
          ),
        );
        await tester.pumpAndSettle();

        // Scope hint defaults to Koramangala
        expect(
          find.text('This expense will be recorded against Koramangala.'),
          findsOneWidget,
        );

        // Fill title and amount
        await tester.enterText(
          find.byType(TextField).at(0),
          'Koramangala Packaging',
        );
        await tester.enterText(find.byType(TextField).at(1), '2000');
        await tester.pumpAndSettle();

        await tester.tap(find.text('Save expense'));
        await tester.pumpAndSettle();

        expect(ownerBloc.dispatchedEvents.length, 1);
        final addEvt = ownerBloc.dispatchedEvents.first as AddExpenseEvent;
        expect(addEvt.title, 'Koramangala Packaging');
        expect(addEvt.amount, 200000);
        expect(addEvt.outletId, 'o2');
        expect(addEvt.orgWide, isFalse);
      },
    );

    testWidgets(
      'ExpensesScreen list displays attribution subtext for both org-wide and outlet-specific bills',
      (tester) async {
        final cache = _FakeLocalCache(allowedOutlets: sampleOutlets);
        final outletCubit = OutletScopeCubit(localCache: cache)
          ..adoptFromLogin(isOwner: true);
        final ownerBloc = _TrackingOwnerBloc(
          OwnerState(
            expenses: [
              Expense(
                id: 'exp-list-1',
                title: 'Hanger Supplies',
                category: 'Supplies',
                amount: 350000,
                due: '2026-10-01',
                outletId: 'o1',
              ),
              Expense(
                id: 'exp-list-2',
                title: 'Business License',
                category: 'Operations',
                amount: 1000000,
                due: '2026-10-01',
                outletId: null, // Org wide
              ),
            ],
          ),
        );
        addTearDown(outletCubit.close);
        addTearDown(ownerBloc.close);

        await tester.pumpWidget(
          buildWrapper(
            child: const ExpensesScreen(),
            ownerBloc: ownerBloc,
            outletScopeCubit: outletCubit,
          ),
        );
        await tester.pumpAndSettle();

        // Both bills show their respective attribution
        expect(find.text('Indiranagar'), findsOneWidget);
        expect(find.text('Organization-wide'), findsOneWidget);
      },
    );
  });
}
