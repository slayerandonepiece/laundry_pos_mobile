import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/core/network/api_client.dart';
import 'package:myshop/core/network/api_exceptions.dart';
import 'package:myshop/core/network/dio_interceptors.dart';
import 'package:myshop/core/storage/local_cache.dart';
import 'package:myshop/core/storage/secure_storage.dart';

import '../helpers/mock_dio.dart';

class TestSecureStorage extends SecureStorageService {
  String? token;

  TestSecureStorage({this.token});

  @override
  Future<String?> getToken() async => token;
}

class TestLocalCache extends LocalCacheService {
  String? storeId;
  String? outletId;

  TestLocalCache({this.storeId, this.outletId});

  @override
  String? getActiveStoreId() => storeId;

  @override
  String? getActiveOutletId() => outletId;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ApiClient with Dio & Interceptors Tests', () {
    test('Interceptors are registered by default on Dio instance', () {
      final apiClient = ApiClient(
        secureStorage: TestSecureStorage(),
        localCache: TestLocalCache(),
      );
      final dio = apiClient.dio;

      expect(dio.interceptors.any((i) => i is AuthInterceptor), isTrue);
      expect(dio.interceptors.any((i) => i is DioLoggingInterceptor), isTrue);
      expect(dio.interceptors.any((i) => i is ErrorInterceptor), isTrue);
    });

    test(
      'AuthInterceptor automatically injects Authorization and X-Store-Id',
      () async {
        String? recordedAuthHeader;
        String? recordedStoreHeader;

        final mockDio = createMockDio((options) async {
          recordedAuthHeader = options.headers['Authorization'] as String?;
          recordedStoreHeader = options.headers['X-Store-Id'] as String?;
          return mockJsonResponse({'ok': true});
        });

        final apiClient = ApiClient(
          dio: mockDio,
          secureStorage: TestSecureStorage(token: 'jwt_mock_token_12345'),
          localCache: TestLocalCache(storeId: 'store_alpha_99'),
        );

        final res = await apiClient.get('https://example.com/api/v1/test');

        expect(res, equals({'ok': true}));
        expect(recordedAuthHeader, equals('Bearer jwt_mock_token_12345'));
        expect(recordedStoreHeader, equals('store_alpha_99'));
      },
    );

    test(
      'Methods GET, POST, PUT, PATCH, DELETE execute and parse response',
      () async {
        final mockDio = createMockDio((options) async {
          final method = options.method;
          return mockJsonResponse({'method': method, 'data': 'success'});
        });

        final apiClient = ApiClient(
          dio: mockDio,
          secureStorage: TestSecureStorage(),
          localCache: TestLocalCache(),
        );

        final getRes = await apiClient.get('https://example.com/test');
        expect(getRes['method'], equals('GET'));

        final postRes = await apiClient.post(
          'https://example.com/test',
          body: {'name': 'wash'},
        );
        expect(postRes['method'], equals('POST'));

        final putRes = await apiClient.put(
          'https://example.com/test',
          body: {'id': 1},
        );
        expect(putRes['method'], equals('PUT'));

        final patchRes = await apiClient.patch(
          'https://example.com/test',
          body: {'status': 'done'},
        );
        expect(patchRes['method'], equals('PATCH'));

        final deleteRes = await apiClient.delete('https://example.com/test');
        expect(deleteRes['method'], equals('DELETE'));
      },
    );

    test(
      '403 error triggers onForbidden and throws AuthException with metadata',
      () async {
        String? forbiddenReason;
        String? forbiddenPaidThrough;

        final mockDio = createMockDio((options) async {
          return mockJsonResponse({
            'error': 'Subscription expired',
            'reason': 'payment_lapsed',
            'paidThroughDate': '2026-03-01',
          }, statusCode: 403);
        });

        final apiClient = ApiClient(
          dio: mockDio,
          secureStorage: TestSecureStorage(),
          localCache: TestLocalCache(),
          onForbidden: (reason, paidThroughDate) {
            forbiddenReason = reason;
            forbiddenPaidThrough = paidThroughDate;
          },
        );

        expect(
          () => apiClient.get('https://example.com/api/v1/owner/metrics'),
          throwsA(
            isA<AuthException>()
                .having((e) => e.code, 'code', 'FORBIDDEN')
                .having((e) => e.statusCode, 'statusCode', 403)
                .having((e) => e.reason, 'reason', 'payment_lapsed')
                .having(
                  (e) => e.paidThroughDate,
                  'paidThroughDate',
                  '2026-03-01',
                ),
          ),
        );

        await pumpEventQueue();
        expect(forbiddenReason, equals('payment_lapsed'));
        expect(forbiddenPaidThrough, equals('2026-03-01'));
      },
    );

    test(
      '400 ValidationException, 404 NotFoundException, 429 RateLimitException',
      () async {
        final mockDio = createMockDio((options) async {
          if (options.uri.path.contains('/bad-request')) {
            return mockJsonResponse({
              'error': 'Invalid request payload',
            }, statusCode: 400);
          }
          if (options.uri.path.contains('/not-found')) {
            return mockJsonResponse({
              'error': 'Order not found',
            }, statusCode: 404);
          }
          if (options.uri.path.contains('/too-many')) {
            return mockJsonResponse({
              'error': 'Too many requests',
            }, statusCode: 429);
          }
          return mockJsonResponse({});
        });

        final apiClient = ApiClient(
          dio: mockDio,
          secureStorage: TestSecureStorage(),
          localCache: TestLocalCache(),
        );

        expect(
          () => apiClient.post('https://example.com/bad-request'),
          throwsA(
            isA<ValidationException>().having(
              (e) => e.message,
              'message',
              'Invalid request payload',
            ),
          ),
        );

        expect(
          () => apiClient.get('https://example.com/not-found'),
          throwsA(
            isA<NotFoundException>().having(
              (e) => e.message,
              'message',
              'Order not found',
            ),
          ),
        );

        expect(
          () => apiClient.get('https://example.com/too-many'),
          throwsA(
            isA<RateLimitException>().having(
              (e) => e.message,
              'message',
              'Too many requests',
            ),
          ),
        );
      },
    );

    test('getRaw returns Uint8List binary response', () async {
      final mockBytes = [0x25, 0x50, 0x44, 0x46]; // %PDF
      final mockDio = createMockDio((options) async {
        return mockBytesResponse(mockBytes, statusCode: 200);
      });

      final apiClient = ApiClient(
        dio: mockDio,
        secureStorage: TestSecureStorage(),
        localCache: TestLocalCache(),
      );
      final raw = await apiClient.getRaw('https://example.com/invoice.pdf');

      expect(raw.statusCode, equals(200));
      expect(raw.bodyBytes, equals(Uint8List.fromList(mockBytes)));
    });

    test(
      'AuthInterceptor omits X-Outlet-Id for kNoOutletHeader and respects explicit override',
      () async {
        bool? hasOutletHeader;
        String? recordedOutletHeader;

        final mockDio = createMockDio((options) async {
          hasOutletHeader = options.headers.containsKey('X-Outlet-Id');
          recordedOutletHeader = options.headers['X-Outlet-Id'] as String?;
          return mockJsonResponse({'ok': true});
        });

        final apiClient = ApiClient(
          dio: mockDio,
          secureStorage: TestSecureStorage(token: 'tok'),
          localCache: TestLocalCache(storeId: 's1', outletId: 'o1'),
        );

        await apiClient.get(
          'https://example.com/api/v1/test',
          headers: {'X-Outlet-Id': kNoOutletHeader},
        );
        expect(hasOutletHeader, isFalse);
        expect(recordedOutletHeader, isNull);

        await apiClient.get(
          'https://example.com/api/v1/test',
          headers: {'X-Outlet-Id': 'o2'},
        );
        expect(hasOutletHeader, isTrue);
        expect(recordedOutletHeader, equals('o2'));
      },
    );
  });
}
