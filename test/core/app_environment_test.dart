import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/core/constants/api_endpoints.dart';
import 'package:myshop/core/constants/app_environment.dart';

void main() {
  group('AppEnvironmentConfig Tests', () {
    test('Default environment resolves to dev', () {
      expect(AppEnvironmentConfig.current, AppEnvironment.dev);
      expect(AppEnvironmentConfig.name, 'dev');
      expect(AppEnvironmentConfig.isDev, isTrue);
      expect(AppEnvironmentConfig.isStage, isFalse);
      expect(AppEnvironmentConfig.isProd, isFalse);
    });

    test('Dev environment points to localhost url', () {
      final localhost = AppEnvironmentConfig.localhostUrl;
      expect(localhost, isNotEmpty);
      expect(localhost.contains('3000'), isTrue);
      expect(AppEnvironmentConfig.baseUrl, localhost);
    });

    test('Stage url and prod url defaults', () {
      expect(AppEnvironmentConfig.stageUrl, anyOf(isEmpty, contains('express-laundry-staging')));
      expect(AppEnvironmentConfig.prodUrl, isEmpty);
    });

    test('ApiEndpoints uses AppEnvironmentConfig base URL', () {
      expect(ApiEndpoints.baseUrl, AppEnvironmentConfig.baseUrl);
      expect(
        ApiEndpoints.login,
        '${AppEnvironmentConfig.baseUrl}/api/v1/auth/login',
      );
      expect(
        ApiEndpoints.orders,
        '${AppEnvironmentConfig.baseUrl}/api/v1/orders',
      );
      expect(
        ApiEndpoints.profile,
        '${AppEnvironmentConfig.baseUrl}/api/v1/profile',
      );
      expect(
        ApiEndpoints.products,
        '${AppEnvironmentConfig.baseUrl}/api/v1/products',
      );
    });
  });
}
