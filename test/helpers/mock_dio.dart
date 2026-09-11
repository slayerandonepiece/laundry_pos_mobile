import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

typedef MockDioHandler = FutureOr<ResponseBody> Function(
  RequestOptions options,
);

/// In-memory mock adapter for Dio tests without requiring real network calls.
class MockDioAdapter implements HttpClientAdapter {
  final MockDioHandler handler;

  MockDioAdapter(this.handler);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return await handler(options);
  }

  @override
  void close({bool force = false}) {}
}

/// Creates a configured [Dio] instance wired to [MockDioAdapter].
Dio createMockDio(MockDioHandler handler) {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 30),
      validateStatus: (status) =>
          status != null && status >= 200 && status < 300,
    ),
  );
  dio.httpClientAdapter = MockDioAdapter(handler);
  return dio;
}

/// Helper to produce a JSON [ResponseBody] for Dio mock responses.
ResponseBody mockJsonResponse(
  dynamic data, {
  int statusCode = 200,
  Map<String, List<String>>? headers,
}) {
  final str = data is String ? data : jsonEncode(data);
  return ResponseBody.fromString(
    str,
    statusCode,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
      ...?headers,
    },
  );
}

/// Helper to produce a raw binary [ResponseBody].
ResponseBody mockBytesResponse(
  List<int> bytes, {
  int statusCode = 200,
  Map<String, List<String>>? headers,
}) {
  return ResponseBody(
    Stream.value(Uint8List.fromList(bytes)),
    statusCode,
    headers: {
      Headers.contentTypeHeader: ['application/octet-stream'],
      ...?headers,
    },
  );
}
