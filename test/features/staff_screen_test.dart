import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/core/network/api_client.dart';
import 'package:myshop/features/owner/bloc/owner_bloc.dart';
import 'package:myshop/features/owner/data/models/staff_model.dart';
import 'package:myshop/features/owner/data/owner_repository.dart';
import 'package:myshop/features/owner/presentation/staff_screen.dart';

class FakeOwnerRepository extends OwnerRepository {
  List<StaffMember> staff = [];
  Map<String, dynamic>? lastCreatedStaff;
  Map<String, dynamic>? lastUpdatedStaff;
  String? lastToggledId;

  FakeOwnerRepository() : super(apiClient: ApiClient());

  @override
  Future<List<StaffMember>> listStaff() async {
    return staff;
  }

  @override
  Future<StaffMember> createStaff({
    required String name,
    required String username,
    required String password,
  }) async {
    lastCreatedStaff = {
      'name': name,
      'username': username,
      'password': password,
    };
    final newMember = StaffMember(
      id: 'emp-${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      username: username,
      active: true,
    );
    staff.add(newMember);
    return newMember;
  }

  @override
  Future<StaffMember> updateStaff({
    required String employeeId,
    required String name,
    required String username,
  }) async {
    lastUpdatedStaff = {
      'employeeId': employeeId,
      'name': name,
      'username': username,
    };
    final index = staff.indexWhere((m) => m.id == employeeId);
    if (index >= 0) {
      final updated = staff[index].copyWith(name: name, username: username);
      staff[index] = updated;
      return updated;
    }
    throw Exception('Staff member not found');
  }

  @override
  Future<void> toggleStaffActive(String employeeId) async {
    lastToggledId = employeeId;
    final index = staff.indexWhere((m) => m.id == employeeId);
    if (index >= 0) {
      staff[index] = staff[index].copyWith(active: !staff[index].active);
    }
  }
}

void main() {
  group('StaffScreen Parity & Full-Screen Tests', () {
    late FakeOwnerRepository fakeRepo;
    late OwnerBloc ownerBloc;

    setUp(() {
      fakeRepo = FakeOwnerRepository();
      fakeRepo.staff = [
        StaffMember(
          id: 'emp-1',
          name: 'Ramesh Kumar',
          username: 'ramesh',
          active: true,
        ),
        StaffMember(
          id: 'emp-2',
          name: 'Priya Sharma',
          username: 'priya',
          active: true,
        ),
        StaffMember(
          id: 'emp-3',
          name: 'Suresh Raina',
          username: 'suresh',
          active: false,
        ),
      ];

      ownerBloc = OwnerBloc(ownerRepository: fakeRepo);
    });

    Widget buildTestWidget() {
      return MaterialApp(
        home: BlocProvider<OwnerBloc>.value(
          value: ownerBloc,
          child: const StaffScreen(),
        ),
      );
    }

    Future<void> pumpStaff(WidgetTester tester) async {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
    }

    testWidgets('Renders subtitle, member list, and footer note', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestWidget());
      await pumpStaff(tester);

      expect(find.text('Staff'), findsOneWidget);
      expect(find.text('3 members'), findsOneWidget);
      expect(
        find.text('Employees can use Sales and manage Orders.'),
        findsOneWidget,
      );

      expect(find.text('Ramesh Kumar'), findsOneWidget);
      expect(find.text('@ramesh · Employee'), findsOneWidget);
      expect(find.text('Priya Sharma'), findsOneWidget);
      expect(find.text('@priya · Employee'), findsOneWidget);
      expect(find.text('Suresh Raina'), findsOneWidget);
      expect(find.text('@suresh · Employee'), findsOneWidget);

      expect(
        find.text('Deactivated employees cannot sign in until reactivated.'),
        findsOneWidget,
      );
    });

    testWidgets('Search box filters by name and username', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await pumpStaff(tester);

      final searchField = find.byType(TextField);
      expect(searchField, findsOneWidget);

      // Search by name 'Priya'
      await tester.enterText(searchField, 'Priya');
      await tester.pumpAndSettle();

      expect(find.text('Priya Sharma'), findsOneWidget);
      expect(find.text('Ramesh Kumar'), findsNothing);
      expect(find.text('Suresh Raina'), findsNothing);

      // Search by username 'suresh'
      await tester.enterText(searchField, 'suresh');
      await tester.pumpAndSettle();

      expect(find.text('Suresh Raina'), findsOneWidget);
      expect(find.text('Priya Sharma'), findsNothing);
      expect(find.text('Ramesh Kumar'), findsNothing);

      // Non-matching query
      await tester.enterText(searchField, 'nonexistent');
      await tester.pumpAndSettle();

      expect(find.text('No staff found'), findsOneWidget);
      expect(find.text('No members match "nonexistent".'), findsOneWidget);
    });

    testWidgets(
      'Tapping Edit opens full-screen edit form pre-filled and dispatches UpdateStaffEvent on save',
      (tester) async {
        await tester.pumpWidget(buildTestWidget());
        await pumpStaff(tester);

        expect(find.byType(Scaffold), findsOneWidget);

        // Tap the first Edit button (for Ramesh)
        final editButtons = find.widgetWithText(OutlinedButton, 'Edit');
        expect(editButtons, findsNWidgets(3));
        await tester.tap(editButtons.first);
        await tester.pumpAndSettle();

        // Full screen checks:
        // 1. EditStaffScreen is pushed
        expect(find.byType(EditStaffScreen), findsOneWidget);
        // 2. Full screen Scaffold exists (2 in tree with offstage)
        expect(find.byType(Scaffold, skipOffstage: false), findsNWidgets(2));
        // 3. No bottom sheet exists
        expect(find.byType(BottomSheet), findsNothing);
        // 4. App bar title
        expect(find.text('Edit staff member'), findsOneWidget);
        // 5. Back arrow in app bar
        expect(find.byIcon(Icons.arrow_back), findsOneWidget);

        // Verify pre-filled values
        expect(find.text('Ramesh Kumar'), findsOneWidget);
        expect(find.text('ramesh'), findsOneWidget);

        // Edit fields
        final fields = find.byType(TextField);
        await tester.enterText(fields.at(0), 'Ramesh K');
        await tester.enterText(fields.at(1), 'rameshk');
        await tester.pumpAndSettle();

        // Tap Save changes
        await tester.tap(find.text('Save changes'));
        await pumpStaff(tester);

        // Verified route popped
        expect(find.byType(EditStaffScreen), findsNothing);
        expect(find.byType(Scaffold), findsOneWidget);

        // Verify repo update was called with correct values
        expect(fakeRepo.lastUpdatedStaff, isNotNull);
        expect(fakeRepo.lastUpdatedStaff!['employeeId'], 'emp-1');
        expect(fakeRepo.lastUpdatedStaff!['name'], 'Ramesh K');
        expect(fakeRepo.lastUpdatedStaff!['username'], 'rameshk');

        // Verify screen displays updated data
        expect(find.text('Ramesh K'), findsOneWidget);
        expect(find.text('@rameshk · Employee'), findsOneWidget);
      },
    );

    testWidgets('Add-staff flow is a full screen (not a bottom sheet)', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestWidget());
      await pumpStaff(tester);

      expect(find.byType(Scaffold), findsOneWidget);

      // Tap + add button in app bar
      final addButton = find.byIcon(Icons.add);
      expect(addButton, findsOneWidget);
      await tester.tap(addButton);
      await tester.pumpAndSettle();

      // Full screen checks:
      // 1. AddStaffScreen is pushed
      expect(find.byType(AddStaffScreen), findsOneWidget);
      // 2. Full screen Scaffold exists (2 in tree with offstage)
      expect(find.byType(Scaffold, skipOffstage: false), findsNWidgets(2));
      // 3. No bottom sheet exists
      expect(find.byType(BottomSheet), findsNothing);
      // 4. App bar title
      expect(find.text('Add staff member'), findsOneWidget);
      // 5. Back arrow in app bar
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);

      // Enter details
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'Anil Verma');
      await tester.enterText(fields.at(1), 'anil');
      await tester.enterText(fields.at(2), 'password123');
      await tester.pumpAndSettle();

      // Tap Create staff account
      await tester.tap(find.text('Create staff account'));
      await pumpStaff(tester);

      // Route popped
      expect(find.byType(AddStaffScreen), findsNothing);
      expect(find.byType(Scaffold), findsOneWidget);

      // Verify repo create was called
      expect(fakeRepo.lastCreatedStaff, isNotNull);
      expect(fakeRepo.lastCreatedStaff!['name'], 'Anil Verma');
      expect(fakeRepo.lastCreatedStaff!['username'], 'anil');
      expect(fakeRepo.lastCreatedStaff!['password'], 'password123');

      // Verify new member is displayed
      expect(find.text('Anil Verma'), findsOneWidget);
      expect(find.text('@anil · Employee'), findsOneWidget);
      expect(find.text('4 members'), findsOneWidget);
    });

    testWidgets('Toggling Active switch dispatches ToggleStaffActiveEvent', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestWidget());
      await pumpStaff(tester);

      final switches = find.byType(Switch);
      expect(switches, findsNWidgets(3));

      // Toggle first member (Ramesh, active: true -> false)
      await tester.tap(switches.first);
      await pumpStaff(tester);

      expect(fakeRepo.lastToggledId, 'emp-1');
      expect(fakeRepo.staff.firstWhere((m) => m.id == 'emp-1').active, isFalse);
    });
  });
}
