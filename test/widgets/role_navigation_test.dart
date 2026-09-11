import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/shared/widgets/bottom_nav.dart';

void main() {
  group('Role Navigation & AppBottomNav Tests', () {
    // Employees now have a single screen (Orders, with its own FAB for new
    // orders) and no bottom bar at all — nothing to test here beyond "the
    // shell doesn't render AppBottomNav for them", which is covered by the
    // shell itself, not this widget.

    testWidgets('Owner sees 3 tabs: Dashboard, Orders, More', (tester) async {
      int selectedTab = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: AppBottomNav(
              currentIndex: selectedTab,
              onTap: (index) => selectedTab = index,
            ),
          ),
        ),
      );

      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.text('New Sale'), findsNothing);
      expect(find.text('Orders'), findsOneWidget);
      expect(find.text('More'), findsOneWidget);

      await tester.tap(find.text('More'));
      expect(selectedTab, equals(2));
    });
  });
}
