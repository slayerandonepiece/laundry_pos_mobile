import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/features/auth/data/models/user_model.dart';
import 'package:myshop/shared/widgets/access_notice_strip.dart';

StoreSummary _store({
  String? state,
  String? trialEndsAt,
  String? paidThroughDate,
  String? blockedReason,
}) => StoreSummary(
  storeId: 's1',
  storeName: 'Test Store',
  role: 'OWNER',
  subscriptionState: state,
  trialEndsAt: trialEndsAt,
  paidThroughDate: paidThroughDate,
  blockedReason: blockedReason,
);

void main() {
  group('resolveAccessNotice', () {
    test('trial shows the end date to everyone, calmly', () {
      for (final isOwner in [true, false]) {
        final notice = resolveAccessNotice(
          _store(state: 'TRIAL', trialEndsAt: '2026-10-15'),
          isOwner: isOwner,
        );
        expect(notice?.message, 'Free trial · Ends 15 Oct 2026');
        expect(notice?.isWarning, isFalse);
      }
    });

    test('trial ending uses the warning tone', () {
      final notice = resolveAccessNotice(
        _store(state: 'TRIAL_ENDING', trialEndsAt: '2026-10-05'),
        isOwner: true,
      );
      expect(notice?.message, 'Free trial · Ends 5 Oct 2026');
      expect(notice?.isWarning, isTrue);
    });

    test('renewal warning gives the owner the date', () {
      final notice = resolveAccessNotice(
        _store(state: 'SUBSCRIPTION_ENDING', paidThroughDate: '2026-10-09'),
        isOwner: true,
      );
      expect(
        notice?.message,
        'Your subscription is due for renewal on 9 Oct 2026. Renew soon to avoid losing access to this store.',
      );
      expect(notice?.isWarning, isTrue);
    });

    test('renewal warning never shows an employee a date or figure', () {
      final notice = resolveAccessNotice(
        _store(state: 'SUBSCRIPTION_ENDING', paidThroughDate: '2026-10-09'),
        isOwner: false,
      );
      expect(
        notice?.message,
        'Billing is due soon for this store. Please check with your store owner.',
      );
      expect(notice!.message, isNot(contains('2026')));
      expect(notice.message, isNot(contains('Oct')));
    });

    test('active, unknown, blocked or missing stores show no strip', () {
      expect(
        resolveAccessNotice(_store(state: 'ACTIVE'), isOwner: true),
        isNull,
      );
      expect(resolveAccessNotice(_store(), isOwner: true), isNull);
      expect(resolveAccessNotice(null, isOwner: true), isNull);
      expect(
        resolveAccessNotice(
          _store(state: 'TRIAL', blockedReason: 'payment_lapsed'),
          isOwner: true,
        ),
        isNull,
      );
    });
  });

  testWidgets('AccessNoticeStrip shows the message', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AccessNoticeStrip(
            notice: AccessNotice('Free trial · Ends 5 Oct 2026'),
          ),
        ),
      ),
    );

    expect(find.text('Free trial · Ends 5 Oct 2026'), findsOneWidget);
  });
}
