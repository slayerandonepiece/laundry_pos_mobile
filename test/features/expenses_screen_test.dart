import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/core/network/api_client.dart';
import 'package:myshop/features/owner/bloc/owner_bloc.dart';
import 'package:myshop/features/owner/data/models/expense_model.dart';
import 'package:myshop/features/owner/data/owner_repository.dart';
import 'package:myshop/features/owner/presentation/expenses_screen.dart';
import 'package:myshop/shared/widgets/centred_dialog.dart';

class FakeOwnerRepository extends OwnerRepository {
  List<Expense> expenses = [];
  String? lastMarkedPaidId;
  Map<String, dynamic>? lastCreatedExpense;

  FakeOwnerRepository() : super(apiClient: ApiClient());

  @override
  Future<List<Expense>> listExpenses() async {
    return expenses;
  }

  @override
  Future<Expense> createExpense({
    required String title,
    required String category,
    required int amount,
    required String due,
    bool monthly = false,
  }) async {
    lastCreatedExpense = {
      'title': title,
      'category': category,
      'amount': amount,
      'due': due,
      'monthly': monthly,
    };
    final newExpense = Expense(
      id: 'exp-${DateTime.now().millisecondsSinceEpoch}',
      title: title,
      category: category,
      amount: amount,
      due: due,
      monthly: monthly,
    );
    expenses.add(newExpense);
    return newExpense;
  }

  @override
  Future<Expense> markExpensePaid(String id) async {
    lastMarkedPaidId = id;
    final index = expenses.indexWhere((e) => e.id == id);
    if (index >= 0) {
      final updated = Expense(
        id: expenses[index].id,
        title: expenses[index].title,
        category: expenses[index].category,
        amount: expenses[index].amount,
        due: expenses[index].due,
        paid: DateTime.now().toIso8601String().split('T')[0],
        monthly: expenses[index].monthly,
      );
      expenses[index] = updated;
      return updated;
    }
    throw Exception('Expense not found');
  }
}

void main() {
  group('ExpensesScreen Parity Tests', () {
    late FakeOwnerRepository fakeRepo;
    late OwnerBloc ownerBloc;

    final now = DateTime.now();
    final todayStr =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    final fourDaysAgo = now.subtract(const Duration(days: 4));
    final fourDaysAgoStr =
        '${fourDaysAgo.year.toString().padLeft(4, '0')}-${fourDaysAgo.month.toString().padLeft(2, '0')}-${fourDaysAgo.day.toString().padLeft(2, '0')}';

    final twentyDaysAgo = now.subtract(const Duration(days: 20));
    final twentyDaysAgoStr =
        '${twentyDaysAgo.year.toString().padLeft(4, '0')}-${twentyDaysAgo.month.toString().padLeft(2, '0')}-${twentyDaysAgo.day.toString().padLeft(2, '0')}';

    setUp(() {
      fakeRepo = FakeOwnerRepository();
      fakeRepo.expenses = [
        Expense(
          id: 'exp-1',
          title: 'Electricity',
          category: 'Utilities',
          amount: 50000, // ₹500
          due: todayStr,
          paid: todayStr,
          monthly: false,
        ),
        Expense(
          id: 'exp-2',
          title: 'Shop Rent',
          category: 'Rent',
          amount: 100000, // ₹1,000
          due: todayStr,
          paid: null,
          monthly: true,
        ),
        Expense(
          id: 'exp-3',
          title: 'Detergent Supplies',
          category: 'Supplies',
          amount: 30000, // ₹300
          due: fourDaysAgoStr,
          paid: fourDaysAgoStr,
          monthly: false,
        ),
        Expense(
          id: 'exp-4',
          title: 'Machine Maintenance',
          category: 'Maintenance',
          amount: 20000, // ₹200
          due: twentyDaysAgoStr,
          paid: null,
          monthly: true,
        ),
      ];

      ownerBloc = OwnerBloc(ownerRepository: fakeRepo);
    });

    Widget buildTestWidget() {
      return MaterialApp(
        home: BlocProvider<OwnerBloc>.value(
          value: ownerBloc,
          child: const ExpensesScreen(),
        ),
      );
    }

    Future<void> pumpExpenses(WidgetTester tester) async {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
    }

    testWidgets('Stats compute correctly across the three period buckets', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildTestWidget());
      await pumpExpenses(tester);

      // Default period is '30d' (This month):
      // Paid in period: exp-1 (₹500) + exp-3 (₹300) = ₹800
      // Unpaid bills in period: exp-2 (₹1,000) + exp-4 (₹200) = ₹1,200
      // Recurring bills shown: exp-2 and exp-4 (both monthly) = 2
      expect(find.text('Paid in selected period'), findsOneWidget);
      expect(find.text('₹800'), findsOneWidget);
      expect(find.text('Unpaid bills in period'), findsOneWidget);
      expect(find.text('₹1,200'), findsOneWidget);
      expect(find.text('Recurring bills shown'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);

      // Switch period to '7d' (Last 7 days)
      await tester.tap(find.text('This month'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Last 7 days').last);
      await tester.pumpAndSettle();

      // In 7d:
      // Paid: exp-1 (₹500) + exp-3 (₹300) = ₹800
      // Unpaid: exp-2 (₹1,000) = ₹1,000
      // Recurring: exp-2 = 1
      expect(find.text('₹800'), findsOneWidget);
      expect(find.text('₹1,000'), findsNWidgets(2)); // Unpaid stat card + exp-2 amount
      expect(find.text('1'), findsOneWidget); // Recurring count

      // Switch period to 'today' (Today)
      await tester.tap(find.text('Last 7 days'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Today').last);
      await tester.pumpAndSettle();

      // In today:
      // Paid: exp-1 (₹500) = ₹500
      // Unpaid: exp-2 (₹1,000) = ₹1,000
      // Recurring: exp-2 = 1
      expect(find.text('₹500'), findsNWidgets(2)); // Paid stat card + exp-1 amount
      expect(find.text('₹1,000'), findsNWidgets(2));
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('Search filters expenses by title and category', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildTestWidget());
      await pumpExpenses(tester);

      // Search by title 'Detergent'
      await tester.enterText(
        find.byType(TextField),
        'Detergent',
      );
      await tester.pumpAndSettle();

      expect(find.text('Detergent Supplies'), findsOneWidget);
      expect(find.text('Electricity'), findsNothing);
      expect(find.text('Shop Rent'), findsNothing);

      // Search by category 'Utilities'
      await tester.enterText(
        find.byType(TextField),
        'Utilities',
      );
      await tester.pumpAndSettle();

      expect(find.text('Electricity'), findsOneWidget);
      expect(find.text('Detergent Supplies'), findsNothing);

      // Non-matching query
      await tester.enterText(
        find.byType(TextField),
        'nonexistent',
      );
      await tester.pumpAndSettle();

      expect(find.text('No expenses match your filters'), findsOneWidget);
    });

    testWidgets('Add-expense flow is a full screen (not a bottom sheet)', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestWidget());
      await pumpExpenses(tester);

      // Before opening, there is 1 Scaffold
      expect(find.byType(Scaffold), findsOneWidget);

      // Tap + add button
      final addButton = find.byIcon(Icons.add);
      expect(addButton, findsOneWidget);
      await tester.tap(addButton);
      await tester.pumpAndSettle();

      // Full screen check:
      // 1. AddExpenseScreen is pushed and visible
      expect(find.byType(AddExpenseScreen), findsOneWidget);
      // 2. A new route with Scaffold is pushed (total 2 Scaffolds in tree including offstage)
      expect(find.byType(Scaffold, skipOffstage: false), findsNWidgets(2));
      // 3. No BottomSheet widget exists
      expect(find.byType(BottomSheet), findsNothing);
      // 4. Screen title is visible
      expect(find.text('Add expense'), findsOneWidget);
      // 5. Back arrow button is in the app bar
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);

      // Fill in and save expense
      final textFields = find.byType(TextField);
      await tester.enterText(textFields.at(0), 'Office Internet');
      await tester.enterText(textFields.at(1), '1500');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save expense'));
      await pumpExpenses(tester);

      // Route popped back to expenses screen
      expect(find.byType(AddExpenseScreen), findsNothing);
      expect(find.byType(Scaffold), findsOneWidget);
      expect(fakeRepo.lastCreatedExpense, isNotNull);
      expect(fakeRepo.lastCreatedExpense!['title'], 'Office Internet');
      expect(fakeRepo.lastCreatedExpense!['amount'], 150000); // 1500 * 100
    });

    testWidgets('Marking an expense paid still works via CentredDialog confirmation', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildTestWidget());
      await pumpExpenses(tester);

      // Tap on unpaid expense 'Shop Rent'
      await tester.tap(find.text('Shop Rent'));
      await tester.pumpAndSettle();

      // Confirmation dialog opens
      expect(find.byType(CentredDialog), findsOneWidget);
      expect(find.text('Mark expense paid?'), findsOneWidget);

      // Tap confirm button 'Mark paid'
      await tester.tap(find.text('Mark paid'));
      await pumpExpenses(tester);

      expect(fakeRepo.lastMarkedPaidId, 'exp-2');
    });
  });
}
