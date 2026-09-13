import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/core/sync/sync_manager.dart';
import 'package:myshop/features/auth/bloc/auth_bloc.dart';
import 'package:myshop/features/auth/bloc/auth_event.dart';
import 'package:myshop/features/auth/bloc/auth_state.dart';
import 'package:myshop/features/auth/data/models/user_model.dart';
import 'package:myshop/features/owner/bloc/owner_bloc.dart';
import 'package:myshop/features/owner/bloc/owner_event.dart';
import 'package:myshop/features/owner/bloc/owner_state.dart';
import 'package:myshop/features/owner/presentation/more_screen.dart';
import 'package:myshop/shared/widgets/sync_status_bar.dart';

class MockAuthBloc extends Bloc<AuthEvent, AuthState> implements AuthBloc {
  MockAuthBloc(super.initialState);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockOwnerBloc extends Bloc<OwnerEvent, OwnerState> implements OwnerBloc {
  MockOwnerBloc() : super(OwnerState()) {
    on<OwnerEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('Sync Direction Banners & Icons', () {
    testWidgets(
      'Displays cloud download icon when message contains cloud pull wording',
      (tester) async {
        SyncManager.instance.startSync('Fetching latest from cloud...');
        expect(
          SyncManager.instance.value.message,
          'Fetching latest from cloud...',
        );

        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: SyncStatusBar())),
        );
        await tester.pump();

        expect(find.byIcon(Icons.cloud_download_rounded), findsOneWidget);
        expect(find.byIcon(Icons.cloud_upload_rounded), findsNothing);
        expect(find.text('Fetching latest from cloud...'), findsOneWidget);

        SyncManager.instance.completeSync();
        await tester.pump(const Duration(seconds: 3));
      },
    );

    testWidgets(
      'Displays cloud upload icon when message contains cloud push wording',
      (tester) async {
        SyncManager.instance.startSync('Saving changes to cloud...');
        expect(
          SyncManager.instance.value.message,
          'Saving changes to cloud...',
        );

        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: SyncStatusBar())),
        );
        await tester.pump();

        expect(find.byIcon(Icons.cloud_upload_rounded), findsOneWidget);
        expect(find.byIcon(Icons.cloud_download_rounded), findsNothing);
        expect(find.text('Saving changes to cloud...'), findsOneWidget);

        SyncManager.instance.completeSync();
        await tester.pump(const Duration(seconds: 3));
      },
    );

    testWidgets(
      'Displays cloud upload icon for batch offline changes wording',
      (tester) async {
        SyncManager.instance.startSync('Syncing 2 of 5 offline changes...');

        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: SyncStatusBar())),
        );
        await tester.pump();

        expect(find.byIcon(Icons.cloud_upload_rounded), findsOneWidget);
        expect(find.text('Syncing 2 of 5 offline changes...'), findsOneWidget);

        SyncManager.instance.completeSync();
        await tester.pump(const Duration(seconds: 3));
      },
    );
  });

  group('MoreScreen Plan Status Badge', () {
    Widget buildMoreScreen(AuthState authState) {
      return MultiBlocProvider(
        providers: [
          BlocProvider<AuthBloc>.value(value: MockAuthBloc(authState)),
          BlocProvider<OwnerBloc>.value(value: MockOwnerBloc()),
        ],
        child: const MaterialApp(home: MoreScreen()),
      );
    }

    final testUser = User(
      id: 'usr-1',
      username: 'owner_user',
      name: 'Jane Doe',
    );

    testWidgets(
      'Active plan badge is rendered when paidThroughDate is > 7 days in future',
      (tester) async {
        final futureDate = DateTime.now().add(const Duration(days: 30));
        final dateStr =
            '${futureDate.year}-${futureDate.month.toString().padLeft(2, '0')}-${futureDate.day.toString().padLeft(2, '0')}';

        final authState = AuthenticatedState(
          user: testUser,
          currentStore: StoreSummary(
            storeId: 'store-1',
            storeName: 'Main Laundromat',
            role: 'OWNER',
            paidThroughDate: dateStr,
          ),
          availableStores: const [],
        );

        await tester.pumpWidget(buildMoreScreen(authState));
        await tester.pumpAndSettle();

        // Badge shows once, in the header row only — not repeated on the
        // Subscription menu item.
        expect(find.text('Active plan'), findsOneWidget);
        expect(find.text('Renews soon'), findsNothing);
      },
    );

    testWidgets(
      'Renews soon warning badge is rendered when paidThroughDate is <= 7 days away',
      (tester) async {
        final nearDate = DateTime.now().add(const Duration(days: 3));
        final dateStr =
            '${nearDate.year}-${nearDate.month.toString().padLeft(2, '0')}-${nearDate.day.toString().padLeft(2, '0')}';

        final authState = AuthenticatedState(
          user: testUser,
          currentStore: StoreSummary(
            storeId: 'store-1',
            storeName: 'Main Laundromat',
            role: 'OWNER',
            paidThroughDate: dateStr,
          ),
          availableStores: const [],
        );

        await tester.pumpWidget(buildMoreScreen(authState));
        await tester.pumpAndSettle();

        // Badge shows once, in the header row only — not repeated on the
        // Subscription menu item.
        expect(find.text('Renews soon'), findsOneWidget);
        expect(find.text('Active plan'), findsNothing);
      },
    );

    testWidgets('No plan badge is rendered when paidThroughDate is null', (
      tester,
    ) async {
      final authState = AuthenticatedState(
        user: testUser,
        currentStore: StoreSummary(
          storeId: 'store-1',
          storeName: 'Main Laundromat',
          role: 'OWNER',
          paidThroughDate: null,
        ),
        availableStores: const [],
      );

      await tester.pumpWidget(buildMoreScreen(authState));
      await tester.pumpAndSettle();

      expect(find.text('Active plan'), findsNothing);
      expect(find.text('Renews soon'), findsNothing);
    });
  });
}
