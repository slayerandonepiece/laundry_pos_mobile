import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/core/sync/sync_manager.dart';
import 'package:myshop/shared/widgets/sync_status_bar.dart';

/// Timer, precedence, pass-through and layout behaviour of [SyncStatusBar].
/// SyncManager is a singleton: it is put back to "synced" (with no bar
/// mounted) before and after every test.
void main() {
  void resetManager() => SyncManager.instance.completeSync(force: true);

  setUp(resetManager);
  tearDown(resetManager);

  Widget app({Widget? content, ThemeData? theme, double? textScale}) {
    Widget home = Scaffold(
      body: Column(
        children: [
          const SyncStatusBar(),
          Expanded(child: content ?? const SizedBox.expand()),
        ],
      ),
    );
    if (textScale != null) {
      home = MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: home,
      );
    }
    return MaterialApp(theme: theme, home: home);
  }

  Finder synced() => find.text('All data synced');

  Future<void> disposeBars(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
  }

  group('"All data synced" banner timer', () {
    testWidgets('lasts ~2s after the LAST completion; an earlier timer cannot '
        'hide a later banner', (tester) async {
      await tester.pumpWidget(app());
      final m = SyncManager.instance;

      m.startSync('a');
      await tester.pump();
      m.completeSync(force: true); // banner #1 at t=0
      await tester.pump();
      expect(synced(), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      m.startSync('b');
      await tester.pump();
      m.completeSync(force: true); // banner #2 at t=1s
      await tester.pump();

      // t=2.5s: banner #1's timer would have fired at 2s.
      await tester.pump(const Duration(milliseconds: 1500));
      expect(synced(), findsOneWidget);

      // t=2.9s (1.9s after the last): still up.
      await tester.pump(const Duration(milliseconds: 400));
      expect(synced(), findsOneWidget);

      // t=3.1s (2.1s after the last): gone.
      await tester.pump(const Duration(milliseconds: 200));
      expect(synced(), findsNothing);
    });

    testWidgets('starting a sync removes the banner immediately and no later '
        'timer resurrects or hides anything', (tester) async {
      await tester.pumpWidget(app());
      final m = SyncManager.instance;
      m.completeSync(force: true);
      await tester.pump();
      expect(synced(), findsOneWidget);

      m.startSync('Syncing again');
      await tester.pump();
      expect(synced(), findsNothing);
      expect(find.text('Syncing again'), findsOneWidget);

      // The old 2s timer passing changes nothing.
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('Syncing again'), findsOneWidget);
    });

    testWidgets('disposing with the timer pending leaves nothing pending and '
        'throws nothing', (tester) async {
      await tester.pumpWidget(app());
      SyncManager.instance.completeSync(force: true);
      await tester.pump();
      expect(synced(), findsOneWidget);

      await disposeBars(tester);
      // No pump(3s) here on purpose: the test binding fails the test if the
      // bar left its timer running.
      expect(tester.takeException(), isNull);
    });

    testWidgets('disposing then pumping past the timer throws nothing', (
      tester,
    ) async {
      await tester.pumpWidget(app());
      SyncManager.instance.completeSync(force: true);
      await tester.pump();
      await disposeBars(tester);
      await tester.pump(const Duration(seconds: 3));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a sync change after dispose is ignored', (tester) async {
      await tester.pumpWidget(app());
      await disposeBars(tester);
      SyncManager.instance.startSync('late');
      await tester.pump(const Duration(seconds: 3));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a notify during layout is applied after the frame, not '
        'thrown', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                const SyncStatusBar(),
                _NotifyDuringLayout(
                  () => SyncManager.instance.startSync('mid-frame'),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      expect(find.text('mid-frame'), findsOneWidget);
    });

    testWidgets('unmounting before the first post-frame show() throws '
        'nothing', (tester) async {
      final key = GlobalKey<_ToggleState>();
      await tester.pumpWidget(
        MaterialApp(
          home: _Toggle(
            key: key,
            onFirstFrame: () {
              // Runs before the bar's own post-frame callback: remove the bar
              // and finalize the tree so the bar is already disposed.
              key.currentState!.hide();
              final owner = WidgetsBinding.instance.buildOwner!;
              owner.buildScope(WidgetsBinding.instance.rootElement!);
              owner.finalizeTree();
            },
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(SyncStatusBar), findsNothing);
    });
  });

  group('precedence and pass-through', () {
    testWidgets('offline wins over the floating banner (one bar, in layout)', (
      tester,
    ) async {
      await tester.pumpWidget(app());
      SyncManager.instance.completeSync(force: true);
      await tester.pump();
      expect(synced(), findsOneWidget);

      SyncManager.instance.setOffline(0);
      await tester.pumpAndSettle();
      expect(
        find.text('Internet is disconnected. Orders will be punched offline.'),
        findsOneWidget,
      );
      expect(synced(), findsNothing);
    });

    for (final (name, apply) in <(String, void Function(SyncManager))>[
      ('error', (m) => m.setError('Boom')),
      ('paused', (m) => m.setSyncPaused(2)),
      ('pending', (m) => m.setPendingOnline(1)),
    ]) {
      testWidgets('$name takes the persistent slot and startSync does not '
          'float over it', (tester) async {
        await tester.pumpWidget(app());
        apply(SyncManager.instance);
        await tester.pumpAndSettle();
        final before = find.byType(Text).evaluate().length;

        SyncManager.instance.startSync('Syncing over it');
        await tester.pumpAndSettle();
        expect(find.text('Syncing over it'), findsNothing);
        expect(find.byType(Text).evaluate().length, before);
      });
    }

    testWidgets('taps pass through the floating bar to content beneath', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        app(
          content: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 300,
              height: 40,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => taps++,
                child: const ColoredBox(color: Colors.red),
              ),
            ),
          ),
        ),
      );
      SyncManager.instance.startSync('Floating');
      await tester.pump(const Duration(milliseconds: 300));
      // Content sits at y=0 (the idle bar has no height); the floating bar is
      // drawn over it.
      final barRect = tester.getRect(
        find
            .ancestor(
              of: find.text('Floating'),
              matching: find.byType(AnimatedContainer),
            )
            .first,
      );
      expect(barRect.top, 0);
      await tester.tapAt(const Offset(50, 10));
      expect(taps, 1);
    });

    testWidgets('the floating bar stays glued to the top after the parent is '
        'resized', (tester) async {
      Widget build(double topGap) => MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              SizedBox(height: topGap),
              const SyncStatusBar(),
              const Expanded(child: SizedBox.expand()),
            ],
          ),
        ),
      );
      await tester.pumpWidget(build(0));
      SyncManager.instance.startSync('Floating');
      await tester.pump(const Duration(milliseconds: 300));
      Rect bar() => tester.getRect(
        find
            .ancestor(
              of: find.text('Floating'),
              matching: find.byType(AnimatedContainer),
            )
            .first,
      );
      expect(bar().top, 0);

      await tester.pumpWidget(build(120));
      await tester.pump(const Duration(milliseconds: 300));
      expect(bar().top, 120);

      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pump(const Duration(milliseconds: 300));
      expect(bar().top, 120);
      expect(bar().left, 0);
      expect(bar().width, 500);
    });

    testWidgets('only the visible tab of an IndexedStack draws the floating '
        'bar', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IndexedStack(
              index: 1,
              children: const [
                Column(children: [SyncStatusBar(), Text('tab0')]),
                Column(children: [SyncStatusBar(), Text('tab1')]),
              ],
            ),
          ),
        ),
      );
      SyncManager.instance.startSync('Floating');
      await tester.pump(const Duration(milliseconds: 300));

      final followers = tester
          .renderObjectList<RenderFollowerLayer>(
            find.byType(CompositedTransformFollower, skipOffstage: false),
          )
          .toList();
      // Two bars; only the visible one has a laid-out leader to follow, and
      // the hidden one is set not to draw when unlinked.
      expect(followers, hasLength(2));
      final drawn = followers.where(
        (f) => f.link.leader != null || f.showWhenUnlinked,
      );
      expect(drawn, hasLength(1));
    });
  });

  group('actionable bar', () {
    for (final (name, apply) in <(String, void Function(SyncManager))>[
      ('pending', (m) => m.setPendingOnline(2)),
      ('paused', (m) => m.setSyncPaused(2)),
      ('error', (m) => m.setError('Boom')),
    ]) {
      testWidgets('$name bar is a 44px tap target that fires onSyncNow', (
        tester,
      ) async {
        var taps = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(children: [SyncStatusBar(onSyncNow: () => taps++)]),
            ),
          ),
        );
        apply(SyncManager.instance);
        await tester.pumpAndSettle();
        final bar = find.byType(AnimatedContainer).first;
        expect(tester.getSize(bar).height, greaterThanOrEqualTo(44));

        // Tap on empty space of the bar, well away from the label link.
        final r = tester.getRect(bar);
        await tester.tapAt(Offset(r.center.dx, r.bottom - 2));
        expect(taps, 1);
      });
    }
  });

  group('text scale and dark theme', () {
    final states = <(String, void Function(SyncManager))>[
      ('syncing', (m) => m.startSync('Fetching the latest orders from cloud')),
      ('synced', (m) => m.completeSync(force: true)),
      ('offline', (m) => m.setOffline(12)),
      ('pending', (m) => m.setPendingOnline(12)),
      ('paused', (m) => m.setSyncPaused(12)),
      ('error', (m) => m.setError('Unable to sync with the server right now')),
    ];
    for (final dark in [false, true]) {
      for (final (name, apply) in states) {
        testWidgets('$name at 2x text, 320pt wide, ${dark ? 'dark' : 'light'}: '
            'no overflow', (tester) async {
          tester.view.physicalSize = const Size(320, 640);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            MaterialApp(
              theme: dark ? ThemeData.dark() : ThemeData.light(),
              home: MediaQuery(
                data: const MediaQueryData(
                  size: Size(320, 640),
                  textScaler: TextScaler.linear(2.0),
                ),
                child: Scaffold(
                  body: Column(
                    children: [
                      SyncStatusBar(onSyncNow: () {}),
                      const Expanded(child: SizedBox.expand()),
                    ],
                  ),
                ),
              ),
            ),
          );
          apply(SyncManager.instance);
          await tester.pump(const Duration(milliseconds: 300));
          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}

class _Toggle extends StatefulWidget {
  final VoidCallback onFirstFrame;
  const _Toggle({super.key, required this.onFirstFrame});
  @override
  State<_Toggle> createState() => _ToggleState();
}

class _ToggleState extends State<_Toggle> {
  bool _show = true;
  void hide() => setState(() => _show = false);

  @override
  void initState() {
    super.initState();
    // Registered before the bar's own callback (parent initState runs first).
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.onFirstFrame());
  }

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Column(children: [if (_show) const SyncStatusBar()]));
}

class _NotifyDuringLayout extends SingleChildRenderObjectWidget {
  final VoidCallback fire;
  const _NotifyDuringLayout(this.fire);
  @override
  RenderObject createRenderObject(BuildContext context) => _RenderNotify(fire);
}

class _RenderNotify extends RenderBox {
  final VoidCallback fire;
  bool _done = false;
  _RenderNotify(this.fire);
  @override
  void performLayout() {
    size = constraints.constrain(const Size(10, 10));
    if (!_done) {
      _done = true;
      assert(
        SchedulerBinding.instance.schedulerPhase ==
            SchedulerPhase.persistentCallbacks,
      );
      fire();
    }
  }
}
