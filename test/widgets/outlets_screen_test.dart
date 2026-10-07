import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:myshop/core/storage/local_cache.dart';
import 'package:myshop/features/owner/presentation/outlets_screen.dart';

void main() {
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('outlets_screen');
    Hive.init(dir.path);
    await Hive.openBox(LocalCacheService.boxName);
  });
  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  testWidgets('lists each outlet with its code', (tester) async {
    await tester.runAsync(() async {
      await LocalCacheService().setActiveStoreId('s');
      await LocalCacheService().setAllowedOutletsForStore('s', [
        {'id': 'o1', 'outletCode': 'HOODI', 'displayName': 'Hoodi'},
        {'id': 'o2', 'outletCode': 'WFLD', 'displayName': 'Whitefield'},
      ]);
    });
    await tester.pumpWidget(const MaterialApp(home: OutletsScreen()));
    await tester.pump();
    expect(find.text('Hoodi'), findsOneWidget);
    expect(find.text('Outlet code WFLD'), findsOneWidget);
    expect(find.text('Active'), findsNWidgets(2));
  });

  testWidgets('says so when there are none', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: OutletsScreen()));
    await tester.pump();
    expect(find.text('No outlets yet'), findsOneWidget);
  });
}
