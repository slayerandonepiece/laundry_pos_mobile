import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/shared/widgets/app_text_field.dart';

void main() {
  // The iOS system context menu throws "Attempted to show while another
  // instance was still visible" when the sign-in screen rebuilds under it
  // after a wrong password. AppTextField must use the Flutter-drawn toolbar.
  testWidgets('AppTextField never uses the iOS system context menu', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'password');
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData.fromView(tester.view)
            .copyWith(supportsShowingSystemContextMenu: true),
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: AppTextField(controller: controller, obscureText: true),
            ),
          ),
        ),
      ),
    );

    // Flutter only offers Paste when the clipboard has something in it.
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.getData') {
          return <String, dynamic>{'text': 'copied elsewhere'};
        }
        if (call.method == 'Clipboard.hasStrings') {
          return <String, dynamic>{'value': true};
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.longPress(find.byType(TextField));
    await tester.pumpAndSettle();

    expect(find.byType(SystemContextMenu), findsNothing);
    expect(find.byType(CupertinoTextSelectionToolbar), findsOneWidget);
    // Paste must stay available so users can paste from anywhere.
    expect(find.text('Paste'), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
}
