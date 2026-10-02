import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kDebugMode, visibleForTesting;

import '../logging/app_logger.dart';
import '../storage/local_cache.dart';
import '../storage/secure_storage.dart';
import 'api_exceptions.dart';
import 'firebase_service.dart';

const _tag = 'DIO';

/// Strips query params before a URL goes into a log line.
String _pathForLog(String url) {
  try {
    final uri = Uri.parse(url);
    return uri.path;
  } catch (_) {
    return url;
  }
}

String _sanitizeHeader(String key, dynamic value) {
  final lower = key.toLowerCase();
  // Never log any part of a credential: logs are forwarded to Crashlytics.
  if (lower == 'authorization' || lower == 'cookie' || lower == 'set-cookie') {
    return '******';
  }
  return value.toString();
}

dynamic _sanitizeBody(dynamic body) {
  if (body is Map) {
    final copy = <String, dynamic>{};
    body.forEach((k, v) {
      final key = k.toString();
      final lower = key.toLowerCase();
      copy[key] =
          lower.contains('password') ||
              lower.contains('secret') ||
              lower.contains('token')
          ? '******'
          : _sanitizeBody(v);
    });
    return copy;
  }
  if (body is List) return body.map(_sanitizeBody).toList();
  return body;
}

/// Bodies of auth endpoints carry tokens, passwords and user PII: never log.
bool _isAuthPath(String path) => path.contains('/auth/');

/// Counts failed round trips (no connection, timeout, 5xx). Repositories
/// swallow such failures and serve their cache, so callers that need to know
/// whether a batch of calls really reached the server compare this counter
/// before and after.
class NetworkHealth {
  NetworkHealth._();
  static int failures = 0;
}

/// Pass as X-Outlet-Id to force the header to be OMITTED (owner, organization-wide) instead of defaulting to the active outlet.
const String kNoOutletHeader = '__no_outlet__';

/// Automatically injects authentication tokens and active store IDs into requests.
class AuthInterceptor extends Interceptor {
  final SecureStorageService _secureStorage;
  final LocalCacheService _localCache;

  AuthInterceptor({
    SecureStorageService? secureStorage,
    LocalCacheService? localCache,
  }) : _secureStorage = secureStorage ?? SecureStorageService(),
       _localCache = localCache ?? LocalCacheService();

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    options.headers.putIfAbsent('Content-Type', () => 'application/json');
    options.headers.putIfAbsent('Accept', () => 'application/json');

    if (!options.headers.containsKey('Authorization')) {
      final token = await _secureStorage.getToken();
      if (token != null && token.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $token';
      }
    }

    if (!options.headers.containsKey('X-Store-Id')) {
      final storeId = _localCache.getActiveStoreId();
      if (storeId != null && storeId.isNotEmpty) {
        options.headers['X-Store-Id'] = storeId;
      }
    }

    // Absence means "All outlets" for an owner — never send an empty
    // string, and never fall back to a default outlet (see O1's employee
    // 403 gate: the server deliberately never guesses either).
    if (options.headers['X-Outlet-Id'] == kNoOutletHeader) {
      options.headers.remove('X-Outlet-Id');
    } else if (!options.headers.containsKey('X-Outlet-Id')) {
      final outletId = _localCache.getActiveOutletId();
      if (outletId != null && outletId.isNotEmpty) {
        options.headers['X-Outlet-Id'] = outletId;
      }
    }

    handler.next(options);
  }
}

/// Formatted, structured logging for Dio HTTP requests, responses, and errors.
class DioLoggingInterceptor extends Interceptor {
  final bool printHeaders;
  final bool printBody;
  final int maxBodyLength;

  /// Report only outside debug builds; debug runs would pollute the stats.
  @visibleForTesting
  static bool reportingEnabled = !kDebugMode;

  /// Where 5xx failures go; replaced in tests.
  @visibleForTesting
  static void Function(Object error, StackTrace? stack, String reason)
  nonFatalReporter = (error, stack, reason) =>
      FirebaseService.recordNonFatal(error, stack, reason: reason);

  DioLoggingInterceptor({
    this.printHeaders = true,
    this.printBody = true,
    this.maxBodyLength = 1000,
  });

  /// Bodies are logged only in debug builds and never for auth endpoints.
  bool _shouldLogBody(String path) =>
      printBody && kDebugMode && !_isAuthPath(path);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra['_startTime'] = Stopwatch()..start();
    final url = _pathForLog(options.uri.toString());
    final method = options.method;

    AppLogger.log(_tag, '--> $method $url');

    if (printHeaders && options.headers.isNotEmpty) {
      final sanitizedHeaders = options.headers.map(
        (k, v) => MapEntry(k, _sanitizeHeader(k, v)),
      );
      AppLogger.log(_tag, '    Headers: $sanitizedHeaders');
    }

    if (_shouldLogBody(options.uri.path) && options.data != null) {
      final sanitized = _sanitizeBody(options.data);
      try {
        final bodyStr = sanitized is String ? sanitized : jsonEncode(sanitized);
        AppLogger.log(_tag, '    Body: ${_truncate(bodyStr)}');
      } catch (_) {
        AppLogger.log(_tag, '    Body: [unserializable]');
      }
    }

    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final stopwatch = response.requestOptions.extra['_startTime'] as Stopwatch?;
    stopwatch?.stop();
    final duration = stopwatch?.elapsedMilliseconds ?? 0;
    final method = response.requestOptions.method;
    final path = _pathForLog(response.requestOptions.uri.toString());
    final statusCode = response.statusCode;

    AppLogger.log(_tag, '<-- $statusCode $method $path in ${duration}ms');

    if (_shouldLogBody(response.requestOptions.uri.path) &&
        response.data != null) {
      try {
        final sanitized = _sanitizeBody(response.data);
        final dataStr = sanitized is String ? sanitized : jsonEncode(sanitized);
        AppLogger.log(_tag, '    Response: ${_truncate(dataStr)}');
      } catch (_) {
        AppLogger.log(_tag, '    Response: [unserializable]');
      }
    }

    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final stopwatch = err.requestOptions.extra['_startTime'] as Stopwatch?;
    stopwatch?.stop();
    final duration = stopwatch?.elapsedMilliseconds ?? 0;
    final method = err.requestOptions.method;
    final path = _pathForLog(err.requestOptions.uri.toString());
    final statusCode = err.response?.statusCode;

    AppLogger.log(
      _tag,
      '<-- ERROR ${statusCode ?? 'ERR'} $method $path in ${duration}ms '
      '(${err.type}): ${err.message}',
      error: err.error,
    );

    if (_shouldLogBody(err.requestOptions.uri.path) &&
        err.response?.data != null) {
      try {
        final sanitized = _sanitizeBody(err.response!.data);
        final dataStr = sanitized is String ? sanitized : jsonEncode(sanitized);
        AppLogger.log(_tag, '    Error Body: ${_truncate(dataStr)}');
      } catch (_) {
        AppLogger.log(_tag, '    Error Body: [unserializable]');
      }
    }

    if (reportingEnabled) {
      // Method, path and status (or error type when there is no response):
      // no query string, no body.
      nonFatalReporter(
        Exception('API ${statusCode ?? err.type.name} $method $path'),
        err.stackTrace,
        '[$_tag] api error',
      );
    }

    handler.next(err);
  }

  String _truncate(String str) {
    if (str.length <= maxBodyLength) return str;
    return '${str.substring(0, maxBodyLength)}... [truncated]';
  }
}

/// Converts HTTP response status codes and network errors into typed [ApiException]s.
class ErrorInterceptor extends Interceptor {
  final void Function()? onUnauthorized;
  final void Function(String? reason, String? paidThroughDate)? onForbidden;
  final void Function()? onInvalidOutlet;

  ErrorInterceptor({
    this.onUnauthorized,
    this.onForbidden,
    this.onInvalidOutlet,
  });

  bool _isAuthEndpoint(String path) {
    return path.contains('/auth/login') ||
        path.contains('/auth/logout') ||
        path.contains('/auth/status');
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final failedStatus = err.response?.statusCode;
    if (failedStatus == null || failedStatus >= 500) NetworkHealth.failures++;

    if (err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.sendTimeout ||
        err.type == DioExceptionType.receiveTimeout) {
      final timeoutException = TimeoutException(
        err.message ?? 'Request timeout',
      );
      return handler.next(err.copyWith(error: timeoutException));
    }

    final response = err.response;
    final statusCode = response?.statusCode;
    final dynamic data = response?.data;

    dynamic decodedData = data;
    if (data is String && data.isNotEmpty) {
      try {
        decodedData = jsonDecode(data);
      } catch (_) {
        decodedData = data;
      }
    }

    String errorMessage = 'Request failed with status $statusCode';
    if (decodedData is Map && decodedData['error'] is String) {
      errorMessage = decodedData['error'] as String;
    } else if (decodedData is String &&
        decodedData.isNotEmpty &&
        !decodedData.trim().startsWith('<')) {
      errorMessage = decodedData;
    } else if (statusCode == 404) {
      errorMessage = 'Server endpoint not found (404). Please verify your server URL or try again later.';
    } else if (statusCode != null && statusCode >= 500) {
      errorMessage = 'Server error ($statusCode). Please try again later.';
    } else if (err.message != null &&
        err.message!.isNotEmpty &&
        !err.message!.contains('validateStatus')) {
      errorMessage = err.message!;
    }

    ApiException appException;

    if (statusCode == 401) {
      final path = err.requestOptions.path;
      if (!_isAuthEndpoint(path)) {
        onUnauthorized?.call();
      }
      appException = AuthException(
        code: 'UNAUTHENTICATED',
        message: errorMessage,
        statusCode: 401,
      );
    } else if (statusCode == 403) {
      String? reason;
      String? paidThroughDate;
      if (decodedData is Map) {
        reason = decodedData['reason']?.toString();
        paidThroughDate = decodedData['paidThroughDate']?.toString();
      }
      onForbidden?.call(reason, paidThroughDate);
      appException = AuthException(
        code: 'FORBIDDEN',
        reason: reason,
        paidThroughDate: paidThroughDate,
        message: errorMessage,
        statusCode: 403,
      );
    } else if (statusCode == 400) {
      if (errorMessage == 'Invalid outlet.') {
        onInvalidOutlet?.call();
      }
      appException = ValidationException(errorMessage);
    } else if (statusCode == 404) {
      appException = NotFoundException(errorMessage);
    } else if (statusCode == 429) {
      appException = RateLimitException(errorMessage);
    } else {
      appException = ApiException(errorMessage, statusCode: statusCode);
    }

    handler.next(err.copyWith(error: appException));
  }
}
