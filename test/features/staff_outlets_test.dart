import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/core/storage/local_cache.dart';
import 'package:myshop/features/owner/bloc/owner_bloc.dart';
import 'package:myshop/features/owner/data/models/staff_model.dart';
import 'package:myshop/features/owner/presentation/staff_screen.dart';
import 'package:myshop/features/shell/bloc/outlet_scope_cubit.dart';

import 'staff_screen_test.dart' show FakeOwnerRepository;

class _Cache extends LocalCacheService {
  _Cache(this.outlets);
  final List<Map<String, dynamic>> outlets;

  @override
  Map<String, dynamic>? getCachedStoreDetails() => {'role': 'OWNER'};
  @override
  List<Map<String, dynamic>>? getAllowedOutlets() => outlets;
  @override
  String? getActiveOutletId() => null;
  @override
  bool isAllOutletsScope() => true;
  @override
  Future<void> setActiveOutletId(String outletId) async {}
  @override
  Future<void> clearActiveOutletId() async {}
  @override
  Future<void> setAllOutletsScope(bool value) async {}
  @override
  Future<void> clearAllOutletsScope() async {}
}

Map<String, dynamic> _outlet(String id, String name) => {
  'id': id,
  'outletCode': id.toUpperCase(),
  'displayName': name,
  'isDefault': false,
  'status': 'ACTIVE',
};

void main() {
  late FakeOwnerRepository repo;
  late OwnerBloc bloc;

  Future<void> pump(
    WidgetTester tester, {
    List<Map<String, dynamic>>? outlets,
  }) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    bloc = OwnerBloc(ownerRepository: repo);
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<OwnerBloc>.value(value: bloc),
          BlocProvider<OutletScopeCubit>(
            create: (_) => OutletScopeCubit(
              localCache: _Cache(
                outlets ??
                    [_outlet('o1', 'Main Road'), _outlet('o2', 'Lake View')],
              ),
            )..hydrate(),
          ),
        ],
        child: const MaterialApp(home: StaffScreen()),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openAdd(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
  }

  Future<void> fillAdd(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField).at(0), 'Nikhil Rao');
    await tester.enterText(find.byType(TextField).at(1), '9000000010');
    await tester.enterText(find.byType(TextField).at(2), 'password123');
  }

  Future<void> save(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  setUp(() {
    repo = FakeOwnerRepository();
    repo.staff = [
      StaffMember(
        id: 'emp-both',
        name: 'Both Outlets',
        phone: '9000000001',
        outlets: const [
          StaffOutlet(id: 'o1', name: 'Main Road'),
          StaffOutlet(id: 'o2', name: 'Lake View'),
        ],
        defaultOutletId: 'o1',
      ),
      StaffMember(
        id: 'emp-none',
        name: 'Nowhere Yet',
        phone: '9000000002',
        outlets: const [],
      ),
      StaffMember(id: 'emp-unknown', name: 'Not Loaded', phone: '9000000003'),
    ];
  });

  group('staff list', () {
    testWidgets("shows each employee's outlets and marks the default", (
      tester,
    ) async {
      await pump(tester);
      expect(find.text('Main Road (default) · Lake View'), findsOneWidget);
    });

    testWidgets('warns about an employee with no outlet access', (
      tester,
    ) async {
      await pump(tester);
      expect(find.text('No outlet access — assign one'), findsOneWidget);
    });

    testWidgets('says nothing for outlets that are not known yet', (
      tester,
    ) async {
      await pump(tester);
      // Only "Nowhere Yet" is warned about; "Not Loaded" is not guessed at.
      expect(find.text('Not Loaded'), findsOneWidget);
      expect(find.text('No outlet access — assign one'), findsOneWidget);
    });
  });

  group('add staff', () {
    testWidgets("lists the owner's outlets, none chosen", (tester) async {
      await pump(tester);
      await openAdd(tester);

      expect(find.text('OUTLETS'), findsOneWidget);
      expect(find.text('Main Road'), findsWidgets);
      expect(find.text('Lake View'), findsWidgets);
      final boxes = tester.widgetList<Checkbox>(find.byType(Checkbox));
      expect(boxes.every((c) => c.value == false), isTrue);
    });

    testWidgets('refuses to create an employee with no outlet', (tester) async {
      await pump(tester);
      await openAdd(tester);
      await fillAdd(tester);

      await save(tester, 'Create staff account');

      expect(
        find.text('Choose at least one outlet they can work in'),
        findsOneWidget,
      );
      expect(repo.lastCreatedStaff, isNull);
    });

    testWidgets('sends the chosen outlets and the default', (tester) async {
      await pump(tester);
      await openAdd(tester);
      await fillAdd(tester);

      await tester.tap(find.byKey(const ValueKey('outlet-o1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('outlet-o2')));
      await tester.pumpAndSettle();
      // The first checked outlet is the default until another is chosen.
      await tester.tap(find.byKey(const ValueKey('default-o2')));
      await tester.pumpAndSettle();

      await save(tester, 'Create staff account');

      expect(repo.lastCreatedStaff!['outletIds'], ['o1', 'o2']);
      expect(repo.lastCreatedStaff!['defaultOutletId'], 'o2');
    });

    testWidgets('unchecking the default moves it to a remaining outlet', (
      tester,
    ) async {
      await pump(tester);
      await openAdd(tester);
      await fillAdd(tester);

      await tester.tap(find.byKey(const ValueKey('outlet-o1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('outlet-o2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('default-o1')));
      await tester.pumpAndSettle();
      // Drop the default outlet.
      await tester.tap(find.byKey(const ValueKey('outlet-o1')));
      await tester.pumpAndSettle();

      await save(tester, 'Create staff account');

      expect(repo.lastCreatedStaff!['outletIds'], ['o2']);
      expect(repo.lastCreatedStaff!['defaultOutletId'], 'o2');
    });

    testWidgets('a one-outlet organization preselects its only outlet', (
      tester,
    ) async {
      await pump(tester, outlets: [_outlet('o1', 'Main Road')]);
      await openAdd(tester);
      await fillAdd(tester);

      await save(tester, 'Create staff account');

      expect(repo.lastCreatedStaff!['outletIds'], ['o1']);
      expect(repo.lastCreatedStaff!['defaultOutletId'], 'o1');
    });
  });

  group('edit staff', () {
    Future<void> openEdit(WidgetTester tester, String name) async {
      final card = find.ancestor(
        of: find.text(name),
        matching: find.byType(Row),
      );
      await tester.tap(
        find.descendant(of: card.first, matching: find.text('Edit')).first,
      );
      await tester.pumpAndSettle();
    }

    testWidgets("shows the employee's current outlets ticked", (tester) async {
      await pump(tester);
      await openEdit(tester, 'Both Outlets');

      expect(find.text('OUTLETS'), findsOneWidget);
      final boxes = tester
          .widgetList<Checkbox>(find.byType(Checkbox))
          .map((c) => c.value)
          .toList();
      expect(boxes, [true, true]);
    });

    testWidgets('a name or phone edit leaves the assignments alone', (
      tester,
    ) async {
      await pump(tester);
      await openEdit(tester, 'Both Outlets');

      await tester.enterText(find.byType(TextField).at(0), 'Both Renamed');
      await save(tester, 'Save changes');

      expect(repo.lastUpdatedStaff!['name'], 'Both Renamed');
      expect(repo.lastUpdatedStaff!['outletIds'], isNull);
      expect(repo.lastUpdatedStaff!['defaultOutletId'], isNull);
    });

    testWidgets('changing outlets sends the new set and default', (
      tester,
    ) async {
      await pump(tester);
      await openEdit(tester, 'Nowhere Yet');

      await tester.tap(find.byKey(const ValueKey('outlet-o2')));
      await tester.pumpAndSettle();
      await save(tester, 'Save changes');

      expect(repo.lastUpdatedStaff!['outletIds'], ['o2']);
      expect(repo.lastUpdatedStaff!['defaultOutletId'], 'o2');
    });

    testWidgets('cannot strip every outlet from an employee', (tester) async {
      await pump(tester);
      await openEdit(tester, 'Both Outlets');

      await tester.tap(find.byKey(const ValueKey('outlet-o1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('outlet-o2')));
      await tester.pumpAndSettle();
      await save(tester, 'Save changes');

      expect(
        find.text('Choose at least one outlet they can work in'),
        findsOneWidget,
      );
      expect(repo.lastUpdatedStaff, isNull);
    });

    testWidgets('unknown assignments are not editable blind', (tester) async {
      await pump(tester);
      await openEdit(tester, 'Not Loaded');

      expect(find.text('OUTLETS'), findsNothing);
    });

    testWidgets('an outlet the employee has but the owner list lacks is kept', (
      tester,
    ) async {
      repo.staff = [
        StaffMember(
          id: 'emp-x',
          name: 'Has Old Outlet',
          phone: '9000000004',
          outlets: const [
            StaffOutlet(id: 'gone', name: 'Old Branch'),
            StaffOutlet(id: 'o1', name: 'Main Road'),
          ],
          defaultOutletId: 'o1',
        ),
      ];
      await pump(tester);
      await openEdit(tester, 'Has Old Outlet');

      expect(find.text('Old Branch'), findsOneWidget);
      // Adding another outlet must not drop the old one.
      await tester.tap(find.byKey(const ValueKey('outlet-o2')));
      await tester.pumpAndSettle();
      await save(tester, 'Save changes');

      expect(
        repo.lastUpdatedStaff!['outletIds'],
        containsAll(['gone', 'o1', 'o2']),
      );
    });
  });
}
