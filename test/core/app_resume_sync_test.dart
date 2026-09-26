import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/core/sync/app_resume_sync.dart';

void main() {
  testWidgets(
    'AppResumeSync calls onResume on AppLifecycleState.resumed and stops after dispose',
    (tester) async {
      var count = 0;
      final resumeSync = AppResumeSync(onResume: () => count++);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      expect(count, 0);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(count, 1);

      resumeSync.dispose();

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(count, 1);
    },
  );
}
