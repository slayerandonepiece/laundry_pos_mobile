import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/core/network/api_exceptions.dart';
import 'package:myshop/features/owner/bloc/owner_bloc.dart';
import 'package:myshop/features/owner/bloc/owner_event.dart';
import 'package:myshop/features/owner/data/owner_repository.dart';

class _ThrowingPasswordRepository implements OwnerRepository {
  Object? toThrow;

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    if (toThrow != null) throw toThrow!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _ThrowingPasswordRepository repo;
  late OwnerBloc bloc;

  setUp(() {
    repo = _ThrowingPasswordRepository();
    bloc = OwnerBloc(ownerRepository: repo);
  });

  tearDown(() => bloc.close());

  Future<String?> submitAndReadError() async {
    bloc.add(
      ChangePasswordSubmittedEvent(
        currentPassword: 'oldpass123',
        newPassword: 'newsecret123',
      ),
    );
    final state = await bloc.stream.firstWhere((s) => s.error != null);
    return state.error;
  }

  test(
    'a throttled change-password attempt shows the wait time from the server',
    () async {
      repo.toThrow = RateLimitException(
        'Too many failed attempts. Try again in 53 seconds.',
      );

      expect(
        await submitAndReadError(),
        'Too many failed attempts. Try again in 53 seconds.',
      );
    },
  );

  test('any other change-password failure keeps the generic message', () async {
    repo.toThrow = Exception('socket closed');

    expect(await submitAndReadError(), 'Could not change password — try again');
  });
}
