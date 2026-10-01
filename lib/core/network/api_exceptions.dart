/// Base API exception
class ApiException implements Exception {
  final String message;
  final int? statusCode;

  ApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

/// Authentication and Authorization exception (401 and 403)
class AuthException extends ApiException {
  final String code; // 'UNAUTHENTICATED' | 'FORBIDDEN'
  final String? reason; // 'membership_inactive' | 'store_locked' | 'store_archived' | 'payment_lapsed' | 'billing_pending'
  final String? paidThroughDate;

  AuthException({
    required this.code,
    this.reason,
    this.paidThroughDate,
    String? message,
    super.statusCode,
  }) : super(
         message ?? (code == 'UNAUTHENTICATED' ? 'Unauthorized' : 'Forbidden'),
       );
}

/// Validation error (400)
class ValidationException extends ApiException {
  ValidationException(super.message) : super(statusCode: 400);
}

/// Resource not found (404)
class NotFoundException extends ApiException {
  NotFoundException(super.message) : super(statusCode: 404);
}

/// Rate limit reached (429)
class RateLimitException extends ApiException {
  RateLimitException(super.message) : super(statusCode: 429);
}
