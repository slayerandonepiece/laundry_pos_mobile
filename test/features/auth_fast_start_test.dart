import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/features/auth/bloc/auth_bloc.dart';
import 'package:myshop/features/auth/bloc/auth_event.dart';
import 'package:myshop/features/auth/bloc/auth_state.dart';
import 'package:myshop/features/auth/data/auth_repository.dart';
import 'package:myshop/features/auth/data/models/user_model.dart';

import 'auth_bloc_forbidden_test.dart'
    show FakeAuthRepository, InMemoryLocalCache;

/// A phone with a saved session and a server that is very slow to answer.
class _SlowServerRepository extends FakeAuthRepository {
  final Completer<void> serverAnswers = Completer<void>();
  int serverChecks = 0;
  AuthResult? saved = AuthResult(
    user: User(id: 'u1', name: 'Priya', phone: 'priya'),
    stores: [
      StoreSummary(storeId: 's1', storeName: 'Saved Store', role: 'OWNER'),
    ],
  );

  @override
  Future<AuthResult?> cachedSession() async => saved;

  @override
  Future<AuthResult?> checkSession() async {
    serverChecks++;
    await serverAnswers.future;
    return super.checkSession();
  }
}

void main() {
  test('opens from the saved session without waiting for the server, then '
      'verifies in the background', () async {
    final repo = _SlowServerRepository();
    final bloc = AuthBloc(
      authRepository: repo,
      localCache: InMemoryLocalCache(),
    );
    addTearDown(bloc.close);

    bloc.add(CheckAuthStatusEvent(fromSavedSession: true));
    final state = await bloc.stream
        .firstWhere((s) => s is AuthenticatedState)
        .timeout(const Duration(seconds: 2));

    expect((state as AuthenticatedState).currentStore.storeName, 'Saved Store');
    // The server has not answered yet; the check is running in the background.
    await pumpEventQueue();
    expect(repo.serverChecks, 1);
    expect(repo.serverAnswers.isCompleted, isFalse);
    repo.serverAnswers.complete();
  });

  test('without a saved session it still asks the server', () async {
    final repo = _SlowServerRepository()..saved = null;
    repo.serverAnswers.complete();
    final bloc = AuthBloc(
      authRepository: repo,
      localCache: InMemoryLocalCache(),
    );
    addTearDown(bloc.close);

    bloc.add(CheckAuthStatusEvent(fromSavedSession: true));
    await bloc.stream.firstWhere((s) => s is AuthenticatedState);
    expect(repo.serverChecks, 1);
  });

  test('a check that is not the app start asks the server, never the saved '
      'session (e.g. right after a forced password change)', () async {
    final repo = _SlowServerRepository();
    repo.serverAnswers.complete();
    final bloc = AuthBloc(
      authRepository: repo,
      localCache: InMemoryLocalCache(),
    );
    addTearDown(bloc.close);

    bloc.add(CheckAuthStatusEvent());
    await bloc.stream.firstWhere((s) => s is AuthenticatedState);
    expect(repo.serverChecks, 1);
  });
}
