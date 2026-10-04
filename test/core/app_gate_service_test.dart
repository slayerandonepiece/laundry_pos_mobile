import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/core/constants/app_environment.dart';
import 'package:myshop/core/gate/app_gate_service.dart';
import 'package:myshop/core/network/firebase_service.dart';
import 'package:myshop/features/orders/bloc/orders_state.dart';
import 'package:myshop/features/pos/bloc/cart_state.dart';
import 'package:myshop/features/pos/data/models/product_model.dart';

void main() {
  group('AppEnvironmentConfig & Single Source of Truth', () {
    test('appName is KlenPOS and is the single source of truth', () {
      expect(AppEnvironmentConfig.appName, equals('KlenPOS'));
    });

    test('FirebaseService default maintenance message uses AppEnvironmentConfig.appName', () {
      expect(
        FirebaseService.maintenanceMessage,
        contains(AppEnvironmentConfig.appName),
      );
      expect(
        FirebaseService.maintenanceMessage,
        equals(
          "KlenPOS is undergoing scheduled maintenance. We'll be back shortly.",
        ),
      );
    });
  });

  group('AppGateService.evaluateGate Order & Fail-Open Behavior', () {
    test(
      'Fails OPEN (GateDecision.proceed) when Remote Config fetch failed',
      () async {
        final decision = await AppGateService.evaluateGate(
          hasSuccessfulFetchOverride: false,
          isMaintenanceModeOverride: true, // Even if maintenance would be true
          isForceUpdateOverride: true,
        );
        expect(decision, equals(GateDecision.proceed));
      },
    );

    test(
      'Maintenance mode has highest priority when fetch succeeded',
      () async {
        final decision = await AppGateService.evaluateGate(
          hasSuccessfulFetchOverride: true,
          isMaintenanceModeOverride: true,
          isForceUpdateOverride: true, // Both maintenance and force-update true
        );
        expect(decision, equals(GateDecision.maintenance));
      },
    );

    test(
      'Proceeds when neither maintenance nor force-update is enabled',
      () async {
        final decision = await AppGateService.evaluateGate(
          hasSuccessfulFetchOverride: true,
          isMaintenanceModeOverride: false,
          isForceUpdateOverride: false,
        );
        expect(decision, equals(GateDecision.proceed));
      },
    );

    test(
      'iOS force update fails OPEN when ios_app_store_id is empty',
      () async {
        final decision = await AppGateService.evaluateGate(
          hasSuccessfulFetchOverride: true,
          isMaintenanceModeOverride: false,
          isForceUpdateOverride: true,
          iosAppStoreIdOverride: '', // Empty store ID
          minSupportedVersionOverride: '2.0.0',
          installedVersionOverride: '1.0.0',
        );
        // Since ios_app_store_id is empty, it must not block
        expect(decision, equals(GateDecision.proceed));
      },
    );

    test(
      'iOS force update fails OPEN when min_supported_version is empty',
      () async {
        final decision = await AppGateService.evaluateGate(
          hasSuccessfulFetchOverride: true,
          isMaintenanceModeOverride: false,
          isForceUpdateOverride: true,
          iosAppStoreIdOverride: '123456789',
          minSupportedVersionOverride: '', // Empty min supported version
          installedVersionOverride: '1.0.0',
        );
        expect(decision, equals(GateDecision.proceed));
      },
    );

    test(
      'iOS force update proceeds when installed version meets min version',
      () async {
        final decision = await AppGateService.evaluateGate(
          hasSuccessfulFetchOverride: true,
          isMaintenanceModeOverride: false,
          isForceUpdateOverride: true,
          iosAppStoreIdOverride: '123456789',
          minSupportedVersionOverride: '1.0.0',
          installedVersionOverride: '1.0.3', // 1.0.3 >= 1.0.0
        );
        expect(decision, equals(GateDecision.proceed));
      },
    );
  });

  group('Version comparison logic', () {
    test('Returns true only when installed < minSupported', () async {
      final below = await AppGateService.isInstalledVersionBelowMinSupported(
        minVersionOverride: '2.0.0',
        installedVersionOverride: '1.0.3',
      );
      expect(below, isTrue);

      final notBelow = await AppGateService.isInstalledVersionBelowMinSupported(
        minVersionOverride: '1.0.0',
        installedVersionOverride: '1.0.3',
      );
      expect(notBelow, isFalse);

      final equal = await AppGateService.isInstalledVersionBelowMinSupported(
        minVersionOverride: '1.0.3',
        installedVersionOverride: '1.0.3',
      );
      expect(equal, isFalse);
    });

    test(
      'Fails OPEN (returns false) on malformed or empty version strings',
      () async {
        final empty = await AppGateService.isInstalledVersionBelowMinSupported(
          minVersionOverride: '',
          installedVersionOverride: '1.0.3',
        );
        expect(empty, isFalse);

        final malformed =
            await AppGateService.isInstalledVersionBelowMinSupported(
              minVersionOverride: 'not-a-valid-version',
              installedVersionOverride: '1.0.3',
            );
        expect(malformed, isFalse);
      },
    );
  });

  group('Mid-Transaction Detection (Resume Listener Guard)', () {
    final sampleProduct = Product(
      id: 'p1',
      name: 'Shirt Wash',
      price: 5000,
      category: 'wash',
      type: 'item',
      active: true,
    );

    test('Reports mid-transaction when CartState has items', () {
      final cartWithItems = CartState(
        items: {'p1': CartItem(product: sampleProduct, quantity: 2)},
      );
      final idleOrders = OrdersState();

      expect(
        AppGateService.isMidTransaction(
          cartState: cartWithItems,
          ordersState: idleOrders,
        ),
        isTrue,
      );
    });

    test('Reports mid-transaction when CartState is submitting checkout', () {
      final submittingCart = CartState(isSubmitting: true);
      final idleOrders = OrdersState();

      expect(
        AppGateService.isMidTransaction(
          cartState: submittingCart,
          ordersState: idleOrders,
        ),
        isTrue,
      );
    });

    test('Reports mid-transaction when OrdersState is collecting payment', () {
      final emptyCart = CartState();
      final collectingOrders = OrdersState(isCollectingPayment: true);

      expect(
        AppGateService.isMidTransaction(
          cartState: emptyCart,
          ordersState: collectingOrders,
        ),
        isTrue,
      );
    });

    test('Reports NOT mid-transaction when cart is empty and no submission/payment is active', () {
      final emptyCart = CartState();
      final idleOrders = OrdersState();

      expect(
        AppGateService.isMidTransaction(
          cartState: emptyCart,
          ordersState: idleOrders,
        ),
        isFalse,
      );
    });
  });
  group('Android InAppUpdate Fail-Open Test', () {
    test('performAndroidForceUpdateIfNeeded handles exceptions gracefully and does not throw', () async {
      // In this test environment (macOS / test runner), InAppUpdate will either no-op or throw PlatformException,
      // and performAndroidForceUpdateIfNeeded must catch and fail open without throwing.
      await expectLater(
        AppGateService.performAndroidForceUpdateIfNeeded(),
        completes,
      );
    });
  });
}
