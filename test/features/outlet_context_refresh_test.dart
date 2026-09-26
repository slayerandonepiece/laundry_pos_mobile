import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/core/network/api_client.dart';
import 'package:myshop/core/storage/local_cache.dart';
import 'package:myshop/core/storage/secure_storage.dart';
import 'package:myshop/features/auth/data/auth_repository.dart';
import 'package:myshop/features/shell/bloc/outlet_scope_cubit.dart';

import '../helpers/mock_dio.dart';

class FakeSecureStorage extends SecureStorageService {
  String? token;

  FakeSecureStorage({this.token = 'tok_123'});

  @override
  Future<String?> getToken() async => token;

  @override
  Future<void> saveToken(String t) async => token = t;

  @override
  Future<void> deleteToken() async => token = null;
}

class InMemoryLocalCache extends LocalCacheService {
  String? _activeStoreId;
  Map<String, dynamic>? _cachedUser;
  Map<String, dynamic>? _cachedStoreDetails;
  List<Map<String, dynamic>>? _cachedAvailableStores;
  final Map<String, List<Map<String, dynamic>>> _outletsByStore = {};
  final Map<String, String?> _activeOutletByStore = {};
  final Map<String, bool> _allOutletsByStore = {};
  bool cleared = false;

  @override
  String? getActiveStoreId() => _activeStoreId;

  @override
  Future<void> setActiveStoreId(String storeId) async {
    _activeStoreId = storeId;
  }

  @override
  Map<String, dynamic>? getCachedUser() => _cachedUser;

  @override
  Future<void> setCachedUser(Map<String, dynamic> userJson) async {
    _cachedUser = userJson;
  }

  @override
  Map<String, dynamic>? getCachedStoreDetails() => _cachedStoreDetails;

  @override
  Future<void> setCachedStoreDetails(Map<String, dynamic> storeJson) async {
    _cachedStoreDetails = storeJson;
  }

  @override
  List<Map<String, dynamic>>? getCachedAvailableStores() =>
      _cachedAvailableStores;

  @override
  Future<void> setCachedAvailableStores(
    List<Map<String, dynamic>> stores,
  ) async {
    _cachedAvailableStores = stores;
  }

  @override
  List<Map<String, dynamic>>? getAllowedOutlets() {
    final s = _activeStoreId ?? 'none';
    return _outletsByStore[s];
  }

  Future<void> setAllowedOutlets(List<Map<String, dynamic>> outlets) async {
    final s = _activeStoreId ?? 'none';
    _outletsByStore[s] = outlets;
  }

  @override
  Future<void> setAllowedOutletsForStore(
    String storeId,
    List<Map<String, dynamic>> outlets,
  ) async {
    _outletsByStore[storeId] = outlets;
  }

  @override
  String? getActiveOutletId() {
    final s = _activeStoreId ?? 'none';
    return _activeOutletByStore[s];
  }

  @override
  Future<void> setActiveOutletId(String outletId) async {
    final s = _activeStoreId ?? 'none';
    _activeOutletByStore[s] = outletId;
  }

  @override
  Future<void> clearActiveOutletId() async {
    final s = _activeStoreId ?? 'none';
    _activeOutletByStore.remove(s);
  }

  @override
  bool isAllOutletsScope() {
    final s = _activeStoreId ?? 'none';
    return _allOutletsByStore[s] ?? false;
  }

  @override
  Future<void> setAllOutletsScope(bool allOutlets) async {
    final s = _activeStoreId ?? 'none';
    _allOutletsByStore[s] = allOutlets;
  }

  @override
  Future<void> clearAllOutletsScope() async {
    final s = _activeStoreId ?? 'none';
    _allOutletsByStore.remove(s);
  }

  @override
  Future<void> clear() async {
    cleared = true;
    _activeStoreId = null;
    _cachedUser = null;
    _cachedStoreDetails = null;
    _cachedAvailableStores = null;
    _outletsByStore.clear();
    _activeOutletByStore.clear();
    _allOutletsByStore.clear();
  }
}

void main() {
  final outlet1 = <String, dynamic>{
    'id': 'o1',
    'outletCode': 'OUT01',
    'displayName': 'Branch One',
    'isDefault': true,
    'status': 'ACTIVE',
  };
  final outlet2 = <String, dynamic>{
    'id': 'o2',
    'outletCode': 'OUT02',
    'displayName': 'Branch Two',
    'isDefault': false,
    'status': 'ACTIVE',
  };

  group('AuthRepository cold-start & refreshOutletContext', () {
    test(
      'checkSession caches organizations[].allowedOutlets per org id; response WITHOUT organizations leaves existing cache untouched',
      () async {
        var includeOrganizations = true;
        final mockDio = createMockDio((options) async {
          return mockJsonResponse({
            'user': {'id': 'u1', 'name': 'User', 'username': 'user'},
            'stores': [
              {'storeId': 's1', 'storeName': 'Store 1', 'role': 'EMPLOYEE'},
              {'storeId': 's2', 'storeName': 'Store 2', 'role': 'OWNER'},
            ],
            if (includeOrganizations)
              'organizations': [
                {
                  'id': 's1',
                  'allowedOutlets': [outlet1],
                },
                {
                  'id': 's2',
                  'allowedOutlets': [outlet1, outlet2],
                },
              ],
          });
        });

        final storage = FakeSecureStorage();
        final cache = InMemoryLocalCache();
        final apiClient = ApiClient(
          dio: mockDio,
          secureStorage: storage,
          localCache: cache,
        );
        final repo = AuthRepository(
          apiClient: apiClient,
          secureStorage: storage,
          localCache: cache,
        );

        final res = await repo.checkSession();
        expect(res, isNotNull);
        expect(cache.getActiveStoreId(), 's1');
        expect(cache.getAllowedOutlets(), equals([outlet1]));

        await cache.setActiveStoreId('s2');
        expect(cache.getAllowedOutlets(), equals([outlet1, outlet2]));

        // Second checkSession WITHOUT 'organizations' key leaves cache untouched
        await cache.setActiveStoreId('s1');
        includeOrganizations = false;
        await repo.checkSession();
        expect(cache.getAllowedOutlets(), equals([outlet1]));
      },
    );

    test(
      'refreshOutletContext returns active store fresh list, null on network error, and calls logout on 401',
      () async {
        var mode = 'ok';
        var logoutPosts = 0;

        final mockDio = createMockDio((options) async {
          if (options.uri.path.contains('/auth/logout')) {
            logoutPosts++;
            return mockJsonResponse({'ok': true});
          }
          if (mode == 'network_error') {
            throw Exception('Connection refused');
          }
          if (mode == '401') {
            return mockJsonResponse({'error': 'Unauthorized'}, statusCode: 401);
          }
          return mockJsonResponse({
            'user': {'id': 'u1', 'name': 'User', 'username': 'user'},
            'stores': [
              {'storeId': 's1', 'storeName': 'Store 1', 'role': 'EMPLOYEE'},
            ],
            'organizations': [
              {
                'id': 's1',
                'allowedOutlets': [outlet2],
              },
            ],
          });
        });

        final storage = FakeSecureStorage();
        final cache = InMemoryLocalCache();
        await cache.setActiveStoreId('s1');
        await cache.setAllowedOutletsForStore('s1', [outlet1]);

        final apiClient = ApiClient(
          dio: mockDio,
          secureStorage: storage,
          localCache: cache,
        );
        final repo = AuthRepository(
          apiClient: apiClient,
          secureStorage: storage,
          localCache: cache,
        );

        final fresh = await repo.refreshOutletContext();
        expect(fresh, equals([outlet2]));
        expect(cache.getAllowedOutlets(), equals([outlet2]));

        mode = 'network_error';
        final onErr = await repo.refreshOutletContext();
        expect(onErr, isNull);
        // Existing cache preserved on network failure
        expect(cache.getAllowedOutlets(), equals([outlet2]));

        mode = '401';
        final on401 = await repo.refreshOutletContext();
        expect(on401, isNull);
        expect(logoutPosts, 1);
        expect(storage.token, isNull);
        expect(cache.cleared, isTrue);
      },
    );
  });

  group('OutletScopeCubit.hydrate() stale activeOutletId handling', () {
    late InMemoryLocalCache cache;
    late OutletScopeCubit cubit;

    setUp(() async {
      cache = InMemoryLocalCache();
      await cache.setActiveStoreId('s1');
      cubit = OutletScopeCubit(localCache: cache);
    });

    tearDown(() => cubit.close());

    test(
      'employee with stale activeOutletId and 1 remaining outlet auto-selects it',
      () async {
        await cache.setCachedStoreDetails({'role': 'EMPLOYEE'});
        await cache.setAllowedOutlets([outlet2]);
        await cache.setActiveOutletId('o_stale');

        cubit.hydrate();

        expect(cache.getActiveOutletId(), 'o2');
        expect(cubit.state.activeOutletId, 'o2');
        expect(cubit.state.requiresSelection, isFalse);
        expect(cubit.state.blockedNoOutlet, isFalse);
      },
    );

    test(
      'employee with stale activeOutletId and 2 remaining outlets requiresSelection',
      () async {
        await cache.setCachedStoreDetails({'role': 'EMPLOYEE'});
        await cache.setAllowedOutlets([outlet1, outlet2]);
        await cache.setActiveOutletId('o_stale');

        cubit.hydrate();

        expect(cache.getActiveOutletId(), isNull);
        expect(cubit.state.activeOutletId, isNull);
        expect(cubit.state.requiresSelection, isTrue);
        expect(cubit.state.blockedNoOutlet, isFalse);
      },
    );

    test(
      'employee with stale activeOutletId and 0 remaining outlets is blockedNoOutlet',
      () async {
        await cache.setCachedStoreDetails({'role': 'EMPLOYEE'});
        await cache.setAllowedOutlets([]);
        await cache.setActiveOutletId('o_stale');

        cubit.hydrate();

        expect(cache.getActiveOutletId(), isNull);
        expect(cubit.state.activeOutletId, isNull);
        expect(cubit.state.blockedNoOutlet, isTrue);
        expect(cubit.state.requiresSelection, isFalse);
      },
    );

    test(
      'owner with stale activeOutletId falls back to All outlets',
      () async {
        await cache.setCachedStoreDetails({'role': 'OWNER'});
        await cache.setAllowedOutlets([outlet1, outlet2]);
        await cache.setActiveOutletId('o_stale');
        await cache.setAllOutletsScope(false);

        cubit.hydrate();

        expect(cache.getActiveOutletId(), isNull);
        expect(cubit.state.activeOutletId, isNull);
        expect(cubit.state.allOutlets, isTrue);
      },
    );
  });
}
