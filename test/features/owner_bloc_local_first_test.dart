import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/features/owner/bloc/owner_bloc.dart';
import 'package:myshop/features/owner/bloc/owner_event.dart';
import 'package:myshop/features/owner/bloc/owner_state.dart';
import 'package:myshop/features/owner/data/models/dashboard_model.dart';
import 'package:myshop/features/owner/data/models/expense_model.dart';
import 'package:myshop/features/owner/data/models/payment_method_model.dart';
import 'package:myshop/features/owner/data/models/staff_model.dart';
import 'package:myshop/features/owner/data/models/store_profile_model.dart';
import 'package:myshop/features/owner/data/owner_repository.dart';

/// Records network calls; `cached*` null means nothing on the phone yet.
class _FakeOwnerRepository implements OwnerRepository {
  DashboardMetrics? cachedMetrics;
  List<Expense>? cachedExpenses;
  List<StaffMember>? cachedStaff;
  List<StorePaymentMethod>? cachedMethods;
  StoreProfile? cachedProfile;
  bool shouldThrowOnStaff = false;
  final List<String> networkCalls = [];

  @override
  DashboardMetrics? getCachedDashboardMetricsSync() => cachedMetrics;
  @override
  List<Expense>? getCachedExpensesSync() => cachedExpenses;
  @override
  List<StaffMember>? getCachedStaffSync() => cachedStaff;
  @override
  List<StorePaymentMethod>? getCachedPaymentMethodsSync() => cachedMethods;
  @override
  StoreProfile? getCachedStoreProfileSync() => cachedProfile;

  @override
  Future<DashboardMetrics> getDashboardMetrics({
    String? from,
    String? to,
  }) async {
    networkCalls.add('dashboard ${from ?? ''}-${to ?? ''}');
    return DashboardMetrics();
  }

  @override
  Future<List<Expense>> listExpenses() async {
    networkCalls.add('expenses');
    return [];
  }

  @override
  Future<List<StaffMember>> listStaff() async {
    networkCalls.add('staff');
    if (shouldThrowOnStaff) throw Exception('network error');
    return [];
  }

  @override
  Future<List<StorePaymentMethod>> listPaymentMethods() async {
    networkCalls.add('payment methods');
    return [];
  }

  @override
  Future<StoreProfile> getStoreProfile() async {
    networkCalls.add('profile');
    return StoreProfile.fromJson(const {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _FakeOwnerRepository repo;
  late OwnerBloc bloc;

  setUp(() {
    repo = _FakeOwnerRepository();
    bloc = OwnerBloc(ownerRepository: repo);
  });

  tearDown(() => bloc.close());

  Future<OwnerState> run(OwnerEvent event) async {
    bloc.add(event);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    return bloc.state;
  }

  void fillCache() {
    repo.cachedMetrics = DashboardMetrics();
    repo.cachedExpenses = [];
    repo.cachedStaff = [];
    repo.cachedMethods = [];
    repo.cachedProfile = StoreProfile.fromJson(const {});
  }

  group('Owner screens open from local data only', () {
    test('Load* with a cache makes no network call', () async {
      fillCache();
      await run(LoadDashboardEvent());
      await run(LoadExpensesEvent());
      await run(LoadStaffEvent());
      await run(LoadPaymentMethodsEvent());
      final state = await run(LoadStoreProfileEvent());

      expect(repo.networkCalls, isEmpty);
      expect(state.storeProfile, isNotNull);
      expect(state.isLoading, isFalse);
    });

    test('refresh: true (pull to refresh / Refresh / Sync now) goes to the network', () async {
      fillCache();
      await run(LoadDashboardEvent(refresh: true));
      await run(LoadExpensesEvent(refresh: true));
      await run(LoadStaffEvent(refresh: true));
      await run(LoadPaymentMethodsEvent(refresh: true));
      await run(LoadStoreProfileEvent(refresh: true));

      expect(repo.networkCalls, [
        'dashboard -',
        'expenses',
        'staff',
        'payment methods',
        'profile',
      ]);
    });

    test('nothing cached yet: fetched once', () async {
      await run(LoadExpensesEvent());
      await run(LoadStaffEvent());
      expect(repo.networkCalls, ['expenses', 'staff']);
    });

    test('a custom dashboard range always fetches', () async {
      fillCache();
      await run(LoadDashboardEvent(from: '2026-09-01', to: '2026-09-10'));
      expect(repo.networkCalls, ['dashboard 2026-09-01-2026-09-10']);
    });

    test(
      'LoadStaffEvent completes done on success, failure, and cache-only path',
      () async {
        // 1. Cache-only path
        fillCache();
        final cCache = Completer<void>();
        bloc.add(LoadStaffEvent(refresh: false, done: cCache));
        await cCache.future;
        expect(cCache.isCompleted, isTrue);

        // 2. Refresh success path
        final cSuccess = Completer<void>();
        bloc.add(LoadStaffEvent(refresh: true, done: cSuccess));
        await cSuccess.future;
        expect(cSuccess.isCompleted, isTrue);

        // 3. Refresh failure path
        repo.shouldThrowOnStaff = true;
        final cFail = Completer<void>();
        bloc.add(LoadStaffEvent(refresh: true, done: cFail));
        await cFail.future;
        expect(cFail.isCompleted, isTrue);
      },
    );
  });
}
