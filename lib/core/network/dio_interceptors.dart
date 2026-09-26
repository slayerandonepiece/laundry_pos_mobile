import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../logging/app_logger.dart';
import '../storage/local_cache.dart';
import '../storage/secure_storage.dart';
import 'api_exceptions.dart';

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
  if (key.toLowerCase() == 'authorization') {
    final str = value.toString();
    if (str.startsWith('Bearer ') && str.length > 15) {
      return 'Bearer ${str.substring(7, 13)}...${str.substring(str.length - 4)}';
    }
    return '******';
  }
  return value.toString();
}

dynamic _sanitizeBody(dynamic body) {
  if (body is Map) {
    final copy = Map<String, dynamic>.from(body);
    for (final key in copy.keys) {
      final lower = key.toLowerCase();
      if (lower.contains('password') ||
          lower.contains('secret') ||
          lower.contains('token')) {
        copy[key] = '******';
      }
    }
    return copy;
  }
  return body;
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

  DioLoggingInterceptor({
    this.printHeaders = true,
    this.printBody = true,
    this.maxBodyLength = 1000,
  });

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra['_startTime'] = Stopwatch()..start();
    final url = options.uri.toString();
    final method = options.method;

    AppLogger.log(_tag, '--> $method $url');

    if (printHeaders && options.headers.isNotEmpty) {
      final sanitizedHeaders = options.headers.map(
        (k, v) => MapEntry(k, _sanitizeHeader(k, v)),
      );
      AppLogger.log(_tag, '    Headers: $sanitizedHeaders');
    }

    if (printBody && options.data != null) {
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

    if (printBody && response.data != null) {
      try {
        final dataStr = response.data is String
            ? response.data as String
            : jsonEncode(response.data);
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

    if (printBody && err.response?.data != null) {
      try {
        final dataStr = err.response!.data is String
            ? err.response!.data as String
            : jsonEncode(err.response!.data);
        AppLogger.log(_tag, '    Error Body: ${_truncate(dataStr)}');
      } catch (_) {
        AppLogger.log(_tag, '    Error Body: [unserializable]');
      }
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
    } else if (decodedData is String && decodedData.isNotEmpty) {
      errorMessage = decodedData;
    } else if (err.message != null && err.message!.isNotEmpty) {
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
        reason = decodedData['reason'] as String?;
        paidThroughDate = decodedData['paidThroughDate'] as String?;
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
