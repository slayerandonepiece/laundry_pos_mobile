import 'package:uuid/uuid.dart';

class IdempotencyKeyGenerator {
  IdempotencyKeyGenerator._();

  static const Uuid _uuid = Uuid();

  /// Generates a new unique idempotency key (UUIDv4)
  static String generate() {
    return _uuid.v4();
  }
}
