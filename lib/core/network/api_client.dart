import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../storage/local_cache.dart';
import '../storage/secure_storage.dart';
import 'api_exceptions.dart';

class ApiClient {
  final http.Client _client;
  final SecureStorageService _secureStorage;
  final LocalCacheService _localCache;
  void Function()? onUnauthorized;
  void Function(String? reason, String? paidThroughDate)? onForbidden;

  // Without this, an unreachable/hanging backend leaves a request in flight
  // for the OS-level TCP timeout (60s+), which — since SyncEngine treats
  // "a sync is in flight" as a lock — makes the whole sync engine look
  // frozen for that entire time instead of failing fast and retrying.
  static const Duration _requestTimeout = Duration(seconds: 15);

  ApiClient({
    http.Client? client,
    SecureStorageService? secureStorage,
    LocalCacheService? localCache,
    this.onUnauthorized,
  }) : _client = client ?? http.Client(),
       _secureStorage = secureStorage ?? SecureStorageService(),
       _localCache = localCache ?? LocalCacheService();

  Future<Map<String, String>> _buildHeaders({
    Map<String, String>? extraHeaders,
  }) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    final token = await _secureStorage.getToken();
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    final storeId = _localCache.getActiveStoreId();
    if (storeId != null && storeId.isNotEmpty) {
      headers['X-Store-Id'] = storeId;
    }

    if (extraHeaders != null) {
      headers.addAll(extraHeaders);
    }
    return headers;
  }

  Future<dynamic> get(String url, {Map<String, String>? headers}) async {
    final requestHeaders = await _buildHeaders(extraHeaders: headers);
    final response = await _client
        .get(Uri.parse(url), headers: requestHeaders)
        .timeout(_requestTimeout);
    return _handleResponse(response, url: url);
  }

  Future<dynamic> post(
    String url, {
    dynamic body,
    Map<String, String>? headers,
  }) async {
    final requestHeaders = await _buildHeaders(extraHeaders: headers);
    final response = await _client
        .post(
          Uri.parse(url),
          headers: requestHeaders,
          body: body != null ? jsonEncode(body) : null,
        )
        .timeout(_requestTimeout);
    return _handleResponse(response, url: url);
  }

  Future<dynamic> put(
    String url, {
    dynamic body,
    Map<String, String>? headers,
  }) async {
    final requestHeaders = await _buildHeaders(extraHeaders: headers);
    final response = await _client
        .put(
          Uri.parse(url),
          headers: requestHeaders,
          body: body != null ? jsonEncode(body) : null,
        )
        .timeout(_requestTimeout);
    return _handleResponse(response, url: url);
  }

  Future<dynamic> patch(
    String url, {
    dynamic body,
    Map<String, String>? headers,
  }) async {
    final requestHeaders = await _buildHeaders(extraHeaders: headers);
    final response = await _client
        .patch(
          Uri.parse(url),
          headers: requestHeaders,
          body: body != null ? jsonEncode(body) : null,
        )
        .timeout(_requestTimeout);
    return _handleResponse(response, url: url);
  }

  Future<dynamic> delete(String url, {Map<String, String>? headers}) async {
    final requestHeaders = await _buildHeaders(extraHeaders: headers);
    final response = await _client
        .delete(Uri.parse(url), headers: requestHeaders)
        .timeout(_requestTimeout);
    return _handleResponse(response, url: url);
  }

  Future<http.Response> getRaw(
    String url, {
    Map<String, String>? headers,
  }) async {
    final requestHeaders = await _buildHeaders(extraHeaders: headers);
    return await _client
        .get(Uri.parse(url), headers: requestHeaders)
        .timeout(_requestTimeout);
  }

  bool _isAuthEndpoint(String? url) {
    if (url == null) return false;
    return url.contains('/auth/login') ||
        url.contains('/auth/logout') ||
        url.contains('/auth/status');
  }

  dynamic _handleResponse(http.Response response, {String? url}) {
    dynamic decodedBody;
    try {
      if (response.body.isNotEmpty) {
        decodedBody = jsonDecode(response.body);
      }
    } catch (_) {
      decodedBody = null;
    }

    final statusCode = response.statusCode;

    if (statusCode >= 200 && statusCode < 300) {
      return decodedBody;
    }

    final errorMessage = (decodedBody is Map && decodedBody['error'] is String)
        ? decodedBody['error'] as String
        : 'Request failed with status $statusCode';

    if (statusCode == 401) {
      if (!_isAuthEndpoint(url)) {
        onUnauthorized?.call();
      }
      throw AuthException(
        code: 'UNAUTHENTICATED',
        message: errorMessage,
        statusCode: 401,
      );
    }

    if (statusCode == 403) {
      final reason = (decodedBody is Map)
          ? decodedBody['reason'] as String?
          : null;
      final paidThroughDate = (decodedBody is Map)
          ? decodedBody['paidThroughDate'] as String?
          : null;
      onForbidden?.call(reason, paidThroughDate);
      throw AuthException(
        code: 'FORBIDDEN',
        reason: reason,
        paidThroughDate: paidThroughDate,
        message: errorMessage,
        statusCode: 403,
      );
    }

    if (statusCode == 400) {
      throw ValidationException(errorMessage);
    }

    if (statusCode == 404) {
      throw NotFoundException(errorMessage);
    }

    if (statusCode == 429) {
      throw RateLimitException(errorMessage);
    }

    throw ApiException(errorMessage, statusCode: statusCode);
  }
}
