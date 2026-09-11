import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../storage/local_cache.dart';
import '../storage/secure_storage.dart';
import 'api_exceptions.dart';
import 'dio_interceptors.dart';

/// Lightweight representation of a raw API response (used for binary downloads like PDFs).
class RawApiResponse {
  final int statusCode;
  final Uint8List bodyBytes;
  final Map<String, List<String>> headers;

  const RawApiResponse({
    required this.statusCode,
    required this.bodyBytes,
    this.headers = const {},
  });

  String get body => utf8.decode(bodyBytes, allowMalformed: true);
}

class ApiClient {
  final Dio _dio;
  final SecureStorageService _secureStorage;
  final LocalCacheService _localCache;

  void Function()? onUnauthorized;
  void Function(String? reason, String? paidThroughDate)? onForbidden;

  static const Duration _requestTimeout = Duration(seconds: 30);

  ApiClient({
    Dio? dio,
    SecureStorageService? secureStorage,
    LocalCacheService? localCache,
    this.onUnauthorized,
    this.onForbidden,
  }) : _secureStorage = secureStorage ?? SecureStorageService(),
       _localCache = localCache ?? LocalCacheService(),
       _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: _requestTimeout,
               receiveTimeout: _requestTimeout,
               sendTimeout: _requestTimeout,
               responseType: ResponseType.json,
               validateStatus: (status) =>
                   status != null && status >= 200 && status < 300,
             ),
           ) {
    _setupInterceptors();
  }

  Dio get dio => _dio;

  void _setupInterceptors() {
    final hasAuth = _dio.interceptors.any((i) => i is AuthInterceptor);
    if (!hasAuth) {
      _dio.interceptors.add(
        AuthInterceptor(secureStorage: _secureStorage, localCache: _localCache),
      );
    }

    final hasLogging = _dio.interceptors.any((i) => i is DioLoggingInterceptor);
    if (!hasLogging) {
      _dio.interceptors.add(
        DioLoggingInterceptor(
          printHeaders: true,
          printBody: true,
          maxBodyLength: 1000,
        ),
      );
    }

    final hasError = _dio.interceptors.any((i) => i is ErrorInterceptor);
    if (!hasError) {
      _dio.interceptors.add(
        ErrorInterceptor(
          onUnauthorized: () => onUnauthorized?.call(),
          onForbidden: (reason, date) => onForbidden?.call(reason, date),
        ),
      );
    }
  }

  dynamic _decodeBody(dynamic data) {
    if (data == null) return null;
    if (data is String) {
      if (data.trim().isEmpty) return null;
      try {
        return jsonDecode(data);
      } catch (_) {
        return data;
      }
    }
    return data;
  }

  Never _handleDioException(DioException e) {
    if (e.error is ApiException) {
      throw e.error!;
    }
    if (e.error is TimeoutException) {
      throw e.error!;
    }
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      throw TimeoutException(
        e.message ?? 'Request timed out after ${_requestTimeout.inSeconds}s',
      );
    }
    throw ApiException(
      e.message ?? 'Network error occurred',
      statusCode: e.response?.statusCode,
    );
  }

  Future<dynamic> get(
    String url, {
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      final response = await _dio.get(
        url,
        queryParameters: queryParameters,
        options: headers != null ? Options(headers: headers) : null,
      );
      return _decodeBody(response.data);
    } on DioException catch (e) {
      _handleDioException(e);
    } catch (e) {
      if (e is ApiException) rethrow;
      rethrow;
    }
  }

  Future<dynamic> post(
    String url, {
    dynamic body,
    Map<String, String>? headers,
  }) async {
    try {
      final response = await _dio.post(
        url,
        data: body,
        options: headers != null ? Options(headers: headers) : null,
      );
      return _decodeBody(response.data);
    } on DioException catch (e) {
      _handleDioException(e);
    } catch (e) {
      if (e is ApiException) rethrow;
      rethrow;
    }
  }

  Future<dynamic> put(
    String url, {
    dynamic body,
    Map<String, String>? headers,
  }) async {
    try {
      final response = await _dio.put(
        url,
        data: body,
        options: headers != null ? Options(headers: headers) : null,
      );
      return _decodeBody(response.data);
    } on DioException catch (e) {
      _handleDioException(e);
    } catch (e) {
      if (e is ApiException) rethrow;
      rethrow;
    }
  }

  Future<dynamic> patch(
    String url, {
    dynamic body,
    Map<String, String>? headers,
  }) async {
    try {
      final response = await _dio.patch(
        url,
        data: body,
        options: headers != null ? Options(headers: headers) : null,
      );
      return _decodeBody(response.data);
    } on DioException catch (e) {
      _handleDioException(e);
    } catch (e) {
      if (e is ApiException) rethrow;
      rethrow;
    }
  }

  Future<dynamic> delete(String url, {Map<String, String>? headers}) async {
    try {
      final response = await _dio.delete(
        url,
        options: headers != null ? Options(headers: headers) : null,
      );
      return _decodeBody(response.data);
    } on DioException catch (e) {
      _handleDioException(e);
    } catch (e) {
      if (e is ApiException) rethrow;
      rethrow;
    }
  }

  Future<RawApiResponse> getRaw(
    String url, {
    Map<String, String>? headers,
  }) async {
    try {
      final response = await _dio.get<List<int>>(
        url,
        options: Options(headers: headers, responseType: ResponseType.bytes),
      );
      final bytes = response.data != null
          ? Uint8List.fromList(response.data!)
          : Uint8List(0);
      return RawApiResponse(
        statusCode: response.statusCode ?? 200,
        bodyBytes: bytes,
        headers: response.headers.map,
      );
    } on DioException catch (e) {
      _handleDioException(e);
    }
  }
}
