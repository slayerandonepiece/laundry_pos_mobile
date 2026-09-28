import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/features/auth/data/models/user_model.dart';
import 'package:myshop/features/owner/presentation/plan_status_helper.dart';

void main() {
  group('StoreSummary Model & PlanStatusHelper Tests', () {
    test('StoreSummary.fromJson parses trialEndsAt and subscriptionState', () {
      final json = {
        'storeId': 'store_1',
        'storeName': 'Quick Wash',
        'role': 'OWNER',
        'blockedReason': null,
        'paidThroughDate': '2026-10-15',
        'trialEndsAt': '2026-10-01',
        'subscriptionState': 'TRIAL_ENDING',
      };

      final store = StoreSummary.fromJson(json);
      expect(store.storeId, 'store_1');
      expect(store.storeName, 'Quick Wash');
      expect(store.role, 'OWNER');
      expect(store.paidThroughDate, '2026-10-15');
      expect(store.trialEndsAt, '2026-10-01');
      expect(store.subscriptionState, 'TRIAL_ENDING');

      final serialized = store.toJson();
      expect(serialized['trialEndsAt'], '2026-10-01');
      expect(serialized['subscriptionState'], 'TRIAL_ENDING');
    });

    test('StoreSummary.fromJson degrades gracefully when trialEndsAt and subscriptionState are absent', () {
      final json = {
        'storeId': 'store_2',
        'storeName': 'Dry Clean Plus',
        'role': 'OWNER',
        'paidThroughDate': '2026-11-01',
      };

      final store = StoreSummary.fromJson(json);
      expect(store.trialEndsAt, isNull);
      expect(store.subscriptionState, isNull);

      final serialized = store.toJson();
      expect(serialized['paidThroughDate'], '2026-11-01');
      expect(serialized['trialEndsAt'], isNull);
      expect(serialized['subscriptionState'], isNull);
    });

    test('resolvePlanStatus: TRIAL returns neutral tone, "Trial" badge, and trialEndsAt', () {
      final store = StoreSummary(
        storeId: 's1',
        storeName: 'Test Store',
        role: 'OWNER',
        subscriptionState: 'TRIAL',
        trialEndsAt: '2026-10-10',
      );

      final status = resolvePlanStatus(store);
      expect(status.isNeutral, isTrue);
      expect(status.badgeLabel, 'Trial');
      expect(status.title, 'Trial');
      expect(status.subtitle, 'Trial ends on 2026-10-10');
    });

    test('resolvePlanStatus: TRIAL_ENDING returns warning tone, "Trial ending" badge, and trialEndsAt', () {
      final store = StoreSummary(
        storeId: 's1',
        storeName: 'Test Store',
        role: 'OWNER',
        subscriptionState: 'TRIAL_ENDING',
        trialEndsAt: '2026-10-02',
        paidThroughDate: '2026-10-15', // Must NOT be used
      );

      final status = resolvePlanStatus(store);
      expect(status.isWarning, isTrue);
      expect(status.badgeLabel, 'Trial ending');
      expect(status.title, 'Trial ending');
      expect(status.subtitle, 'Please keep payment updated. Trial ends on 2026-10-02.');
    });

    test('resolvePlanStatus: SUBSCRIPTION_ENDING returns warning tone, "Renews soon" badge, and paidThroughDate', () {
      final store = StoreSummary(
        storeId: 's1',
        storeName: 'Test Store',
        role: 'OWNER',
        subscriptionState: 'SUBSCRIPTION_ENDING',
        paidThroughDate: '2026-10-05',
      );

      final status = resolvePlanStatus(store);
      expect(status.isWarning, isTrue);
      expect(status.badgeLabel, 'Renews soon');
      expect(status.title, 'Your plan renews soon');
      expect(status.subtitle, 'Please keep payment updated. Renews on 2026-10-05.');
    });

    test('resolvePlanStatus: RESTRICTED returns unavailable tone and no badge', () {
      final store = StoreSummary(
        storeId: 's1',
        storeName: 'Test Store',
        role: 'OWNER',
        subscriptionState: 'RESTRICTED',
      );

      final status = resolvePlanStatus(store);
      expect(status.isUnavailable, isTrue);
      expect(status.badgeLabel, isNull);
    });

    test('resolvePlanStatus: ACTIVE falls back to paidThroughDate logic', () {
      final farDate = DateTime.now().add(const Duration(days: 20));
      final farDateStr = '${farDate.year}-${farDate.month.toString().padLeft(2, '0')}-${farDate.day.toString().padLeft(2, '0')}';
      final storeActiveFar = StoreSummary(
        storeId: 's1',
        storeName: 'Test Store',
        role: 'OWNER',
        subscriptionState: 'ACTIVE',
        paidThroughDate: farDateStr,
      );

      final statusFar = resolvePlanStatus(storeActiveFar);
      expect(statusFar.isSuccess, isTrue);
      expect(statusFar.badgeLabel, 'Active plan');
      expect(statusFar.title, 'Your plan is active');
      expect(statusFar.subtitle, 'Renews on $farDateStr');

      final nearDate = DateTime.now().add(const Duration(days: 2));
      final nearDateStr = '${nearDate.year}-${nearDate.month.toString().padLeft(2, '0')}-${nearDate.day.toString().padLeft(2, '0')}';
      final storeActiveNear = StoreSummary(
        storeId: 's1',
        storeName: 'Test Store',
        role: 'OWNER',
        subscriptionState: 'ACTIVE',
        paidThroughDate: nearDateStr,
      );

      final statusNear = resolvePlanStatus(storeActiveNear);
      expect(statusNear.isWarning, isTrue);
      expect(statusNear.badgeLabel, 'Renews soon');
      expect(statusNear.title, 'Your plan renews soon');
    });

    test('resolvePlanStatus: null subscriptionState falls back to paidThroughDate logic', () {
      final farDate = DateTime.now().add(const Duration(days: 20));
      final farDateStr = '${farDate.year}-${farDate.month.toString().padLeft(2, '0')}-${farDate.day.toString().padLeft(2, '0')}';
      final storeNullFar = StoreSummary(
        storeId: 's1',
        storeName: 'Test Store',
        role: 'OWNER',
        paidThroughDate: farDateStr,
      );

      final statusFar = resolvePlanStatus(storeNullFar);
      expect(statusFar.isSuccess, isTrue);
      expect(statusFar.badgeLabel, 'Active plan');

      final storeNullDate = StoreSummary(
        storeId: 's1',
        storeName: 'Test Store',
        role: 'OWNER',
        paidThroughDate: null,
      );

      final statusNull = resolvePlanStatus(storeNullDate);
      expect(statusNull.isUnavailable, isTrue);
      expect(statusNull.badgeLabel, isNull);
    });
  });
}
