import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/core/sync/sync_manager.dart';
import 'package:myshop/shared/widgets/sync_status_bar.dart';

void main() {
  group('SyncStatusBar & SyncManager Tests', () {
    setUp(() {
      SyncManager.instance.completeSync();
    });

    testWidgets('Renders syncing state with progress spinner and message', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Column(children: [SyncStatusBar()])),
        ),
      );

      // Initially synced -> collapsed after timeout
      await tester.pumpAndSettle();

      // Trigger sync
      SyncManager.instance.startSync('Syncing products...');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Syncing products...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets(
      'Renders offline state with disconnected message and no sync now button',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(children: [SyncStatusBar(onSyncNow: () {})]),
            ),
          ),
        );

        SyncManager.instance.setOffline(3);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(
          find.text(
            'Internet is disconnected. Orders will be punched offline.',
          ),
          findsOneWidget,
        );
        expect(find.text('Sync now'), findsNothing);
        expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);
      },
    );

    testWidgets(
      'Renders pendingOnline state with change count and active sync now button',
      (tester) async {
        bool syncNowTapped = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  SyncStatusBar(
                    onSyncNow: () {
                      syncNowTapped = true;
                    },
                  ),
                ],
              ),
            ),
          ),
        );

        SyncManager.instance.setPendingOnline(3);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('3 changes pending'), findsOneWidget);
        expect(find.text('Sync now'), findsOneWidget);
        expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);

        await tester.tap(find.text('Sync now'));
        await tester.pump();

        expect(syncNowTapped, isTrue);
      },
    );

    testWidgets('Renders error state with danger styling', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Column(children: [SyncStatusBar()])),
        ),
      );

      SyncManager.instance.setError('Unable to sync with server');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Unable to sync with server'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    });
  });
}
