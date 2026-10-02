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
      expect(
        AppEnvironmentConfig.stageUrl,
        anyOf(isEmpty, contains('klenpos-staging')),
      );
      expect(AppEnvironmentConfig.stageUrl.endsWith('/'), isFalse);
      expect(AppEnvironmentConfig.prodUrl.endsWith('/'), isFalse);
      expect(AppEnvironmentConfig.baseUrl.endsWith('/'), isFalse);
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

    group('flavor decides the environment', () {
      test('stage and prod flavors can never run as dev', () {
        expect(
          AppEnvironmentConfig.resolveEnvironment(flavor: 'prod'),
          AppEnvironment.prod,
        );
        expect(
          AppEnvironmentConfig.resolveEnvironment(flavor: 'stage'),
          AppEnvironment.stage,
        );
        // Even a wrong ENV cannot pull a prod flavor back to dev.
        expect(
          AppEnvironmentConfig.resolveEnvironment(
            flavor: 'prod',
            explicit: 'dev',
          ),
          AppEnvironment.prod,
        );
      });

      test('dev flavor and no flavor follow ENV, defaulting to dev', () {
        expect(AppEnvironmentConfig.resolveEnvironment(), AppEnvironment.dev);
        expect(
          AppEnvironmentConfig.resolveEnvironment(explicit: 'prod'),
          AppEnvironment.prod,
        );
        expect(
          AppEnvironmentConfig.resolveEnvironment(
            flavor: 'dev',
            explicit: 'stage',
          ),
          AppEnvironment.stage,
        );
        expect(
          AppEnvironmentConfig.resolveEnvironment(flavor: 'dev'),
          AppEnvironment.dev,
        );
      });
    });

    group('plain HTTP is for dev only', () {
      test('dev may use an http override', () {
        expect(
          AppEnvironmentConfig.resolveBaseUrl(
            env: AppEnvironment.dev,
            override: 'http://192.168.1.20:3100/',
          ),
          'http://192.168.1.20:3100',
        );
      });

      test('stage and prod ignore a non-https override', () {
        expect(
          AppEnvironmentConfig.resolveBaseUrl(
            env: AppEnvironment.prod,
            override: 'http://evil.example.com',
          ),
          AppEnvironmentConfig.prodUrl,
        );
        expect(
          AppEnvironmentConfig.resolveBaseUrl(
            env: AppEnvironment.stage,
            override: 'http://10.0.2.2:3000',
          ),
          AppEnvironmentConfig.stageUrl,
        );
      });

      test('stage and prod accept an https override', () {
        expect(
          AppEnvironmentConfig.resolveBaseUrl(
            env: AppEnvironment.prod,
            override: 'https://api.klenpos.example/',
          ),
          'https://api.klenpos.example',
        );
      });

      test('the real stage and prod defaults are https', () {
        expect(AppEnvironmentConfig.stageUrl, startsWith('https://'));
        expect(AppEnvironmentConfig.prodUrl, startsWith('https://'));
      });
    });
  });
}
