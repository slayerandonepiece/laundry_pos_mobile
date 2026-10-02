import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/core/error/crash_context.dart';
import 'package:myshop/features/auth/data/models/user_model.dart';

class _FakeSink implements CrashContextSink {
  final identifiers = <String>[];
  final keys = <String, Object>{};
  final analyticsIds = <String?>[];
  final analyticsRoles = <String?>[];

  @override
  Future<void> setAnalyticsRole(String? role) async => analyticsRoles.add(role);

  @override
  Future<void> setAnalyticsUserId(String? userId) async =>
      analyticsIds.add(userId);

  @override
  Future<void> setCrashKey(String key, Object value) async {
    keys[key] = value;
  }

  @override
  Future<void> setCrashUserIdentifier(String identifier) async =>
      identifiers.add(identifier);
}

void main() {
  late _FakeSink sink;

  setUp(() {
    sink = _FakeSink();
    CrashContext.sink = sink;
  });

  test('sets exact owner context without name or phone', () async {
    final user = User(
      id: 'opaque-owner-id',
      name: 'Distinctive Owner Name',
      phone: '+919876543210',
    );
    await CrashContext.setAuthenticated(
      userId: user.id,
      storeId: 'store-1',
      outletId: 'outlet-2',
      role: 'owner',
      environment: 'stage',
    );

    expect(sink.identifiers, ['opaque-owner-id']);
    expect(sink.keys, {
      'store_id': 'store-1',
      'outlet_id': 'outlet-2',
      'role': 'OWNER',
      'environment': 'stage',
    });
    expect(sink.analyticsIds, ['opaque-owner-id']);
    expect(sink.analyticsRoles, ['OWNER']);
    final transmitted = [
      ...sink.identifiers,
      ...sink.keys.values.map((value) => value.toString()),
      ...sink.analyticsIds.map((value) => value.toString()),
      ...sink.analyticsRoles.map((value) => value.toString()),
    ];
    expect(transmitted, isNot(contains(user.name)));
    expect(transmitted, isNot(contains(user.phone)));
  });

  test('sets exact employee context and neutral missing outlet', () async {
    await CrashContext.setAuthenticated(
      userId: 'opaque-employee-id',
      storeId: 'store-9',
      role: 'employee',
      environment: 'prod',
    );

    expect(sink.keys, {
      'store_id': 'store-9',
      'outlet_id': '',
      'role': 'EMPLOYEE',
      'environment': 'prod',
    });
    expect(sink.analyticsRoles, ['EMPLOYEE']);
  });

  test('sign-out clears identifier, keys, and analytics identity', () async {
    await CrashContext.clear();

    expect(sink.identifiers, ['']);
    expect(sink.keys, {
      'store_id': '',
      'outlet_id': '',
      'role': '',
      'environment': '',
    });
    expect(sink.analyticsIds, [null]);
    expect(sink.analyticsRoles, [null]);
  });
}
