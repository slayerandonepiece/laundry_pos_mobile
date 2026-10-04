import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/features/update/presentation/update_required_screen.dart';

Widget _host(Future<UpdateAttempt> Function() onUpdate) =>
    MaterialApp(home: UpdateRequiredScreen(onUpdate: onUpdate));

const _button = Key('update_required_button');
const _error = Key('update_required_error');

void main() {
  testWidgets('shows the mandatory message and one Update now button', (
    tester,
  ) async {
    await tester.pumpWidget(_host(() async => UpdateAttempt.opened));
    expect(find.text('Update required'), findsOneWidget);
    expect(find.textContaining('no longer supported'), findsOneWidget);
    expect(find.byKey(_button), findsOneWidget);
    expect(find.text('Later'), findsNothing);
    expect(find.byKey(_error), findsNothing);
  });

  testWidgets('Update now runs once, even if tapped repeatedly', (
    tester,
  ) async {
    final pending = Completer<UpdateAttempt>();
    var calls = 0;
    await tester.pumpWidget(
      _host(() {
        calls += 1;
        return pending.future;
      }),
    );
    await tester.tap(find.byKey(_button));
    await tester.pump();
    await tester.tap(find.byKey(_button));
    await tester.pump();
    expect(calls, 1);
    pending.complete(UpdateAttempt.opened);
    await tester.pump();
    expect(find.byKey(_error), findsNothing);
  });

  testWidgets('no internet says so, stays put, and can be retried', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      _host(() async {
        calls += 1;
        return UpdateAttempt.offline;
      }),
    );
    await tester.tap(find.byKey(_button));
    await tester.pumpAndSettle();
    expect(
      find.text('No internet connection. Connect and try again.'),
      findsOneWidget,
    );
    expect(find.text('Update required'), findsOneWidget);

    await tester.tap(find.byKey(_button));
    await tester.pumpAndSettle();
    expect(calls, 2, reason: 'the user can try again');
  });

  testWidgets('a store that cannot open shows a retry hint and stays put', (
    tester,
  ) async {
    await tester.pumpWidget(_host(() async => UpdateAttempt.failed));
    await tester.tap(find.byKey(_button));
    await tester.pumpAndSettle();
    expect(
      find.text("Couldn't open the App Store. Try again."),
      findsOneWidget,
    );
    expect(find.text('Update required'), findsOneWidget);
  });

  testWidgets('gives up after the time limit instead of spinning forever', (
    tester,
  ) async {
    await tester.pumpWidget(_host(() => Completer<UpdateAttempt>().future));
    await tester.tap(find.byKey(_button));
    await tester.pump();
    expect(find.byKey(_error), findsNothing, reason: 'still waiting');

    await tester.pump(kUpdateAttemptTimeout + const Duration(seconds: 1));
    expect(find.byKey(_error), findsOneWidget);
    // And the button works again.
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNotNull,
    );
  });

  testWidgets('cannot be dismissed with the back gesture', (tester) async {
    await tester.pumpWidget(_host(() async => UpdateAttempt.opened));
    final popScope = tester.widget<PopScope>(find.byType(PopScope).first);
    expect(popScope.canPop, isFalse);
  });
}
