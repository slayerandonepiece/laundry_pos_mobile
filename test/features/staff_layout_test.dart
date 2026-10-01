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
  @override
  Map<String, dynamic>? getCachedStoreDetails() => {'role': 'OWNER'};
  @override
  List<Map<String, dynamic>>? getAllowedOutlets() => [
    for (final (id, name) in [('o1', 'Main Road'), ('o2', 'Lake View')])
      {
        'id': id,
        'outletCode': id.toUpperCase(),
        'displayName': name,
        'isDefault': false,
        'status': 'ACTIVE',
      },
  ];
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

void main() {
  late FakeOwnerRepository repo;

  setUp(() {
    repo = FakeOwnerRepository()
      ..staff = [
        StaffMember(
          id: 'blank-names',
          name: 'Blank Names',
          phone: '9000000001',
          outlets: const [
            StaffOutlet(id: 'o1', name: ''),
            StaffOutlet(id: '', name: ''),
            StaffOutlet(id: 'o2', name: '   '),
          ],
          defaultOutletId: 'o1',
        ),
        StaffMember(
          id: 'all-blank',
          name: 'All Blank',
          phone: '9000000002',
          outlets: const [StaffOutlet(id: '', name: '')],
        ),
      ];
  });

  Future<void> pump(
    WidgetTester tester, {
    Size size = const Size(800, 2000),
    double textScale = 1,
    bool dark = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<OwnerBloc>(
            create: (_) => OwnerBloc(ownerRepository: repo),
          ),
          BlocProvider<OutletScopeCubit>(
            create: (_) => OutletScopeCubit(localCache: _Cache())..hydrate(),
          ),
        ],
        child: MaterialApp(
          theme: dark ? ThemeData.dark() : ThemeData.light(),
          home: const StaffScreen(),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'outlet summary never shows blank names or a dangling separator',
    (tester) async {
      await pump(tester);
      // Blank names fall back to the id; an outlet with neither is skipped.
      expect(find.text('o1 (default) · o2'), findsOneWidget);
      // An employee whose only outlet is fully blank shows no summary at all.
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data);
      expect(texts.where((t) => t != null && t.trim() == '·'), isEmpty);
      expect(
        texts.where(
          (t) => t != null && (t.startsWith(' ·') || t.endsWith('· ')),
        ),
        isEmpty,
      );
    },
  );

  testWidgets('Edit has a 44px-high tap target', (tester) async {
    await pump(tester);
    final button = find.ancestor(
      of: find.text('Edit').first,
      matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
    );
    expect(tester.getSize(button.first).height, greaterThanOrEqualTo(44));
  });

  testWidgets(
    '320px staff card keeps phone to one line and both forms show the full helper',
    (tester) async {
      repo.staff[0] = StaffMember(
        id: 'long-name',
        name: 'An Extremely Long Employee Name For A Narrow Phone',
        phone: '90000000011234567890',
        outlets: const [StaffOutlet(id: 'o1', name: 'Main Road')],
        defaultOutletId: 'o1',
      );
      await pump(tester, size: const Size(320, 800));
      expect(tester.takeException(), isNull);
      final phone = tester.widget<Text>(find.text('90000000011234567890'));
      expect(phone.maxLines, 1);
      expect(phone.overflow, TextOverflow.ellipsis);
      final edit = find.ancestor(
        of: find.text('Edit').first,
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      );
      expect(tester.getSize(edit.first).height, greaterThanOrEqualTo(44));
      expect(
        tester.getSize(find.byType(Switch).first).width,
        greaterThanOrEqualTo(44),
      );

      const helper =
          'They can only sign in to the checked outlets. The one marked Default opens first.';
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(helper));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.text(helper)).right, lessThanOrEqualTo(320));
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit').first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(helper));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.text(helper)).right, lessThanOrEqualTo(320));
      expect(tester.takeException(), isNull);
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      '320x568 at 1.5x text (${dark ? 'dark' : 'light'}): list, add and edit '
      'forms lay out; keyboard open keeps OUTLETS and the button reachable',
      (tester) async {
        await pump(
          tester,
          size: const Size(320, 568),
          textScale: 1.5,
          dark: dark,
        );
        expect(tester.takeException(), isNull);

        // Add form with the keyboard up (300px of the screen taken).
        await tester.tap(find.byIcon(Icons.add));
        await tester.pumpAndSettle();
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('OUTLETS'));
        await tester.pumpAndSettle();
        expect(tester.getRect(find.text('OUTLETS')).bottom, lessThan(268));
        await tester.ensureVisible(find.text('Create staff account'));
        await tester.pumpAndSettle();
        expect(
          tester.getRect(find.text('Create staff account')).bottom,
          lessThanOrEqualTo(268),
        );
        expect(tester.takeException(), isNull);

        // Edit form.
        tester.view.resetViewInsets();
        await tester.tap(find.byIcon(Icons.arrow_back));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Edit').first);
        await tester.pumpAndSettle();
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Save changes'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          tester.getRect(find.text('Save changes')).bottom,
          lessThanOrEqualTo(268),
        );
      },
    );
  }
}
