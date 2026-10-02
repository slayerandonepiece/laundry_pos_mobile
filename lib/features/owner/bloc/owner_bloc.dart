import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:myshop/core/logging/app_logger.dart';
import 'package:myshop/core/network/api_exceptions.dart';
import 'package:myshop/features/owner/data/models/dashboard_model.dart';
import 'package:myshop/features/owner/data/owner_repository.dart';

import 'owner_event.dart';
import 'owner_state.dart';

const _tag = 'OWNER_BLOC';

class OwnerBloc extends Bloc<OwnerEvent, OwnerState> {
  final OwnerRepository ownerRepository;

  OwnerBloc({required this.ownerRepository}) : super(OwnerState()) {
    on<LoadDashboardEvent>(_onLoadDashboard);
    on<LoadOutletRollupsEvent>(_onLoadOutletRollups);
    on<LoadCardMetricsEvent>(_onLoadCardMetrics);
    on<LoadPreviousPeriodEvent>(_onLoadPreviousPeriod);
    on<ResetCardEvent>(_onResetCard);
    on<LoadExpensesEvent>(_onLoadExpenses);
    on<AddExpenseEvent>(_onAddExpense);
    on<UpdateExpenseEvent>(_onUpdateExpense);
    on<DeleteExpenseEvent>(_onDeleteExpense);
    on<MarkExpensePaidEvent>(_onMarkExpensePaid);
    on<LoadStaffEvent>(_onLoadStaff);
    on<AddStaffEvent>(_onAddStaff);
    on<ToggleStaffActiveEvent>(_onToggleStaffActive);
    on<UpdateStaffEvent>(_onUpdateStaff);
    on<LoadPaymentMethodsEvent>(_onLoadPaymentMethods);
    on<TogglePaymentMethodEvent>(_onTogglePaymentMethod);
    on<LoadStoreProfileEvent>(_onLoadStoreProfile);
    on<UpdateStoreProfileEvent>(_onUpdateStoreProfile);
    on<ChangePasswordSubmittedEvent>(_onChangePasswordSubmitted);
  }

  /// The most recent dashboard selection asked for. Handlers run
  /// concurrently, so a reply (or failure) for an older selection must not
  /// overwrite what a newer one already showed.
  String? _latestDashboardKey;

  static const _queuedMessage =
      'Saved offline — will sync when you\'re back online';

  /// [online] normally; the "saved offline" wording when the repository only
  /// queued the write. Read straight after the write.
  String _writeMessage(String online) =>
      OwnerRepository.lastWriteQueued ? _queuedMessage : online;

  /// What to tell the owner about a failed write: the server's own message
  /// for validation / conflict rejections (duplicate phone, invalid outlet,
  /// last outlet...), a refusal's message as is, else [fallback].
  String _failure(Object e, String fallback) {
    if (e is OwnerRefusedException) return e.message;
    if (e is ApiException &&
        e is! AuthException &&
        const {400, 409, 422}.contains(e.statusCode) &&
        e.message.trim().isNotEmpty) {
      return e.message;
    }
    return fallback;
  }

  Set<OwnerSection> _addLoading(OwnerSection section) => {
    ...state.loading,
    section,
  };

  Set<OwnerSection> _removeLoading(OwnerSection section) =>
      {...state.loading}..remove(section);

  Future<void> _onLoadDashboard(
    LoadDashboardEvent event,
    Emitter<OwnerState> emit,
  ) async {
    if (event.requestKey != null) _latestDashboardKey = event.requestKey;
    bool superseded() =>
        event.requestKey != null && event.requestKey != _latestDashboardKey;
    try {
      // Opening the screen shows the cache only; the network is used on
      // refresh, for any non-default period (only the default period is
      // cached), or when nothing is cached yet.
      final cachedMetrics = event.isDefaultPeriod
          ? ownerRepository.getCachedDashboardMetricsSync()
          : null;
      if (cachedMetrics != null) {
        emit(
          state.copyWith(
            metrics: cachedMetrics,
            dashboardKey: event.requestKey,
            error: null,
          ),
        );
        if (!event.refresh) return;
      } else {
        emit(
          state.copyWith(
            loading: _addLoading(OwnerSection.dashboard),
            error: null,
          ),
        );
      }
      try {
        final metrics = await ownerRepository.getDashboardMetrics(
          from: event.from,
          to: event.to,
          granularity: event.granularity,
        );
        if (superseded()) return;
        emit(
          state.copyWith(
            loading: _removeLoading(OwnerSection.dashboard),
            metrics: metrics,
            dashboardKey: event.requestKey,
          ),
        );
      } catch (e) {
        AppLogger.log(_tag, 'load dashboard failed', error: e);
        if (superseded()) return;
        // A 401 means the session is gone (signing out): the auth flow deals
        // with that, and a "try again" message would linger on the sign-in
        // screen.
        final sessionLost = e is AuthException && e.statusCode == 401;
        final err = cachedMetrics == null && !sessionLost
            ? 'Could not load dashboard — try again'
            : null;
        // Nothing on the phone and the request failed: the metrics held are
        // another outlet's. Drop them rather than leave the screen waiting
        // for a reply that isn't coming (it would stay dimmed for good).
        final holdsOtherSelection =
            cachedMetrics == null &&
            event.requestKey != null &&
            state.dashboardKey != event.requestKey;
        emit(
          state.copyWith(
            loading: _removeLoading(OwnerSection.dashboard),
            error: err,
            messageSection: err != null ? OwnerSection.dashboard : null,
            metrics: holdsOtherSelection ? DashboardMetrics() : null,
            dashboardKey: holdsOtherSelection ? event.requestKey : null,
          ),
        );
      }
    } finally {
      if (event.done != null && !event.done!.isCompleted) {
        event.done!.complete();
      }
    }
  }

  Future<void> _onLoadOutletRollups(
    LoadOutletRollupsEvent event,
    Emitter<OwnerState> emit,
  ) async {
    if (!event.allOutlets) {
      emit(
        state.copyWith(
          outletRollups: const [],
          outletRollupsLoading: false,
          outletRollupsFailed: false,
        ),
      );
      return;
    }
    emit(
      state.copyWith(outletRollupsLoading: true, outletRollupsFailed: false),
    );
    try {
      final rollups = await ownerRepository.getOutletRollups(
        from: event.from,
        to: event.to,
      );
      emit(
        state.copyWith(
          outletRollups: rollups,
          outletRollupsLoading: false,
          outletRollupsFailed: false,
        ),
      );
    } catch (e) {
      AppLogger.log(_tag, 'load outlet rollups failed', error: e);
      emit(
        state.copyWith(
          outletRollups: const [],
          outletRollupsLoading: false,
          outletRollupsFailed: true,
        ),
      );
    }
  }

  Future<void> _onLoadCardMetrics(
    LoadCardMetricsEvent event,
    Emitter<OwnerState> emit,
  ) async {
    emit(
      state.copyWith(
        cards: {
          ...state.cards,
          event.card: CardMetrics(key: event.requestKey),
        },
      ),
    );
    try {
      final metrics = await ownerRepository.getPeriodMetrics(
        from: event.range.fromIso,
        to: event.range.toIso,
        granularity: event.range.granularity,
      );
      // The selection moved on while this was in flight: not for this card.
      if (state.cards[event.card]?.key != event.requestKey) return;
      emit(
        state.copyWith(
          cards: {
            ...state.cards,
            event.card: CardMetrics(key: event.requestKey, metrics: metrics),
          },
        ),
      );
    } catch (e) {
      AppLogger.log(_tag, 'load card ${event.card.name} failed', error: e);
      if (state.cards[event.card]?.key != event.requestKey) return;
      emit(
        state.copyWith(
          cards: {
            ...state.cards,
            event.card: CardMetrics(key: event.requestKey, failed: true),
          },
        ),
      );
    }
  }

  /// The comparison window is as long as the selected range (its end capped at
  /// today) and ends the day before the range starts, like the web dashboard.
  /// UTC dates keep a daylight-saving change from shifting a day.
  Future<void> _onLoadPreviousPeriod(
    LoadPreviousPeriodEvent event,
    Emitter<OwnerState> emit,
  ) async {
    emit(state.copyWith(previousKey: event.requestKey, previousBars: const []));
    try {
      DateTime day(DateTime d) => DateTime.utc(d.year, d.month, d.day);
      final from = day(DateTime.parse(event.range.fromIso));
      final to = day(DateTime.parse(event.range.toIso));
      final today = day(DateTime.now());
      final end = to.isBefore(today) ? to : today;
      final span = end.difference(from).inDays + 1;
      final length = span < 1 ? 1 : span;
      String iso(DateTime d) => d.toIso8601String().substring(0, 10);
      final metrics = await ownerRepository.getPeriodMetrics(
        from: iso(from.subtract(Duration(days: length))),
        to: iso(from.subtract(const Duration(days: 1))),
        granularity: event.range.granularity,
      );
      // The selection moved on while this was in flight: not for this chart.
      if (state.previousKey != event.requestKey) return;
      emit(state.copyWith(previousBars: metrics.bars));
    } catch (e) {
      // Comparison is a nicety: no previous line, and no error for the page.
      AppLogger.log(_tag, 'load previous period failed', error: e);
    }
  }

  void _onResetCard(ResetCardEvent event, Emitter<OwnerState> emit) {
    if (!state.cards.keys.any(event.cards.contains)) return;
    emit(
      state.copyWith(
        cards: {...state.cards}..removeWhere((k, _) => event.cards.contains(k)),
      ),
    );
  }

  Future<void> _onLoadExpenses(
    LoadExpensesEvent event,
    Emitter<OwnerState> emit,
  ) async {
    try {
      final cachedExpenses = ownerRepository.getCachedExpensesSync();
      if (cachedExpenses != null) {
        emit(state.copyWith(expenses: cachedExpenses, error: null));
        if (!event.refresh) return;
      } else {
        emit(
          state.copyWith(
            loading: _addLoading(OwnerSection.expenses),
            error: null,
          ),
        );
      }
      try {
        final expenses = await ownerRepository.listExpenses();
        emit(
          state.copyWith(
            loading: _removeLoading(OwnerSection.expenses),
            expenses: expenses,
          ),
        );
      } catch (e) {
        AppLogger.log(_tag, 'load expenses failed', error: e);
        final err = cachedExpenses == null
            ? 'Could not load expenses — try again'
            : null;
        emit(
          state.copyWith(
            loading: _removeLoading(OwnerSection.expenses),
            error: err,
            messageSection: err != null ? OwnerSection.expenses : null,
          ),
        );
      }
    } finally {
      if (event.done != null && !event.done!.isCompleted) {
        event.done!.complete();
      }
    }
  }

  Future<void> _onAddExpense(
    AddExpenseEvent event,
    Emitter<OwnerState> emit,
  ) async {
    emit(
      state.copyWith(loading: _addLoading(OwnerSection.expenses), error: null),
    );
    try {
      await ownerRepository.createExpense(
        title: event.title,
        category: event.category,
        amount: event.amount,
        due: event.due,
        monthly: event.monthly,
        idempotencyKey: event.idempotencyKey,
        outletId: event.outletId,
        orgWide: event.orgWide,
      );
      final message = _writeMessage('Expense recorded successfully');
      final updated = await ownerRepository.listExpenses();
      emit(
        state.copyWith(
          loading: _removeLoading(OwnerSection.expenses),
          expenses: updated,
          actionMessage: message,
          messageSection: OwnerSection.expenses,
        ),
      );
    } catch (e) {
      AppLogger.log(_tag, 'add expense failed', error: e);
      emit(
        state.copyWith(
          loading: _removeLoading(OwnerSection.expenses),
          error: _failure(e, 'Could not add expense — try again'),
          messageSection: OwnerSection.expenses,
        ),
      );
    }
  }

  Future<void> _onUpdateExpense(
    UpdateExpenseEvent event,
    Emitter<OwnerState> emit,
  ) async {
    emit(
      state.copyWith(loading: _addLoading(OwnerSection.expenses), error: null),
    );
    try {
      await ownerRepository.updateExpense(
        event.expenseId,
        title: event.title,
        category: event.category,
        amount: event.amount,
        due: event.due,
        outletId: event.outletId,
      );
      final message = _writeMessage('Expense updated');
      final updated = await ownerRepository.listExpenses();
      emit(
        state.copyWith(
          loading: _removeLoading(OwnerSection.expenses),
          expenses: updated,
          actionMessage: message,
          messageSection: OwnerSection.expenses,
        ),
      );
    } catch (e) {
      AppLogger.log(_tag, 'update expense failed', error: e);
      emit(
        state.copyWith(
          loading: _removeLoading(OwnerSection.expenses),
          error: _failure(e, 'Could not update expense — try again'),
          messageSection: OwnerSection.expenses,
        ),
      );
    }
  }

  Future<void> _onDeleteExpense(
    DeleteExpenseEvent event,
    Emitter<OwnerState> emit,
  ) async {
    emit(
      state.copyWith(loading: _addLoading(OwnerSection.expenses), error: null),
    );
    try {
      await ownerRepository.deleteExpense(event.expenseId);
      final message = _writeMessage('Expense deleted');
      final updated = await ownerRepository.listExpenses();
      emit(
        state.copyWith(
          loading: _removeLoading(OwnerSection.expenses),
          expenses: updated,
          actionMessage: message,
          messageSection: OwnerSection.expenses,
        ),
      );
    } catch (e) {
      AppLogger.log(_tag, 'delete expense failed', error: e);
      emit(
        state.copyWith(
          loading: _removeLoading(OwnerSection.expenses),
          error: _failure(e, 'Could not delete expense — try again'),
          messageSection: OwnerSection.expenses,
        ),
      );
    }
  }

  Future<void> _onMarkExpensePaid(
    MarkExpensePaidEvent event,
    Emitter<OwnerState> emit,
  ) async {
    emit(
      state.copyWith(loading: _addLoading(OwnerSection.expenses), error: null),
    );
    try {
      await ownerRepository.markExpensePaid(
        event.expenseId,
        paidDate: event.paidDate,
      );
      final message = _writeMessage('Expense marked paid');
      final updated = await ownerRepository.listExpenses();
      emit(
        state.copyWith(
          loading: _removeLoading(OwnerSection.expenses),
          expenses: updated,
          actionMessage: message,
          messageSection: OwnerSection.expenses,
        ),
      );
    } catch (e) {
      AppLogger.log(_tag, 'mark expense paid failed', error: e);
      emit(
        state.copyWith(
          loading: _removeLoading(OwnerSection.expenses),
          error: _failure(e, 'Could not mark expense paid — try again'),
          messageSection: OwnerSection.expenses,
        ),
      );
    }
  }

  Future<void> _onLoadStaff(
    LoadStaffEvent event,
    Emitter<OwnerState> emit,
  ) async {
    try {
      final cachedStaff = ownerRepository.getCachedStaffSync();
      if (cachedStaff != null) {
        emit(state.copyWith(staff: cachedStaff, error: null));
        // A list cached before assignments were kept has no outlet facts:
        // fetch once so the badges and warnings are real, not guessed.
        final lacksOutlets = cachedStaff.any((m) => m.outlets == null);
        if (!event.refresh && !lacksOutlets) return;
      } else {
        emit(
          state.copyWith(loading: _addLoading(OwnerSection.staff), error: null),
        );
      }
      try {
        final staff = await ownerRepository.listStaff();
        emit(
          state.copyWith(
            loading: _removeLoading(OwnerSection.staff),
            staff: staff,
          ),
        );
      } catch (e) {
        AppLogger.log(_tag, 'load staff failed', error: e);
        final err = cachedStaff == null
            ? 'Could not load staff — try again'
            : null;
        emit(
          state.copyWith(
            loading: _removeLoading(OwnerSection.staff),
            error: err,
            messageSection: err != null ? OwnerSection.staff : null,
          ),
        );
      }
    } finally {
      if (event.done != null && !event.done!.isCompleted) {
        event.done!.complete();
      }
    }
  }

  Future<void> _onAddStaff(
    AddStaffEvent event,
    Emitter<OwnerState> emit,
  ) async {
    emit(state.copyWith(loading: _addLoading(OwnerSection.staff), error: null));
    try {
      await ownerRepository.createStaff(
        name: event.name,
        phone: event.phone,
        password: event.password,
        idempotencyKey: event.idempotencyKey,
        outletIds: event.outletIds,
        defaultOutletId: event.defaultOutletId,
      );
      final message = _writeMessage('Staff member added successfully');
      final updated = await ownerRepository.listStaff();
      emit(
        state.copyWith(
          loading: _removeLoading(OwnerSection.staff),
          staff: updated,
          actionMessage: message,
          messageSection: OwnerSection.staff,
        ),
      );
    } catch (e) {
      AppLogger.log(_tag, 'add staff failed', error: e);
      final isOfflineError = e.toString().contains(
        'Adding staff needs an internet connection',
      );
      emit(
        state.copyWith(
          loading: _removeLoading(OwnerSection.staff),
          error: isOfflineError
              ? 'Adding staff needs an internet connection'
              : _failure(e, 'Could not add staff — try again'),
          messageSection: OwnerSection.staff,
        ),
      );
    }
  }

  Future<void> _onToggleStaffActive(
    ToggleStaffActiveEvent event,
    Emitter<OwnerState> emit,
  ) async {
    emit(state.copyWith(loading: _addLoading(OwnerSection.staff), error: null));
    try {
      await ownerRepository.toggleStaffActive(event.employeeId);
      final queued = OwnerRepository.lastWriteQueued;
      final updated = await ownerRepository.listStaff();
      emit(
        state.copyWith(
          loading: _removeLoading(OwnerSection.staff),
          staff: updated,
          actionMessage: queued ? _queuedMessage : null,
          messageSection: queued ? OwnerSection.staff : null,
        ),
      );
    } catch (e) {
      AppLogger.log(_tag, 'toggle staff active failed', error: e);
      emit(
        state.copyWith(
          loading: _removeLoading(OwnerSection.staff),
          error: _failure(e, 'Could not update staff status — try again'),
          messageSection: OwnerSection.staff,
        ),
      );
    }
  }

  Future<void> _onUpdateStaff(
    UpdateStaffEvent event,
    Emitter<OwnerState> emit,
  ) async {
    emit(state.copyWith(loading: _addLoading(OwnerSection.staff), error: null));
    try {
      await ownerRepository.updateStaff(
        employeeId: event.employeeId,
        name: event.name,
        phone: event.phone,
        password: event.password,
        outletIds: event.outletIds,
        defaultOutletId: event.defaultOutletId,
      );
      final message = _writeMessage(
        event.password?.isNotEmpty == true
            ? 'Staff member updated. Sessions end; they must set a new password at next sign-in'
            : 'Staff member updated successfully',
      );
      final updated = await ownerRepository.listStaff();
      emit(
        state.copyWith(
          loading: _removeLoading(OwnerSection.staff),
          staff: updated,
          actionMessage: message,
          messageSection: OwnerSection.staff,
        ),
      );
    } catch (e) {
      AppLogger.log(_tag, 'update staff failed', error: e);
      emit(
        state.copyWith(
          loading: _removeLoading(OwnerSection.staff),
          error: _failure(e, 'Could not update staff — try again'),
          messageSection: OwnerSection.staff,
        ),
      );
    }
  }

  Future<void> _onLoadPaymentMethods(
    LoadPaymentMethodsEvent event,
    Emitter<OwnerState> emit,
  ) async {
    try {
      final cachedMethods = ownerRepository.getCachedPaymentMethodsSync();
      if (cachedMethods != null) {
        emit(state.copyWith(paymentMethods: cachedMethods, error: null));
        if (!event.refresh) return;
      } else {
        emit(
          state.copyWith(
            loading: _addLoading(OwnerSection.paymentMethods),
            error: null,
          ),
        );
      }
      try {
        final methods = await ownerRepository.listPaymentMethods();
        emit(
          state.copyWith(
            loading: _removeLoading(OwnerSection.paymentMethods),
            paymentMethods: methods,
          ),
        );
      } catch (e) {
        AppLogger.log(_tag, 'load payment methods failed', error: e);
        final err = cachedMethods == null
            ? 'Could not load payment methods — try again'
            : null;
        emit(
          state.copyWith(
            loading: _removeLoading(OwnerSection.paymentMethods),
            error: err,
            messageSection: err != null ? OwnerSection.paymentMethods : null,
          ),
        );
      }
    } finally {
      if (event.done != null && !event.done!.isCompleted) {
        event.done!.complete();
      }
    }
  }

  Future<void> _onTogglePaymentMethod(
    TogglePaymentMethodEvent event,
    Emitter<OwnerState> emit,
  ) async {
    emit(
      state.copyWith(
        loading: _addLoading(OwnerSection.paymentMethods),
        error: null,
      ),
    );
    try {
      await ownerRepository.togglePaymentMethod(event.id, event.active);
      final queued = OwnerRepository.lastWriteQueued;
      final updated = await ownerRepository.listPaymentMethods();
      emit(
        state.copyWith(
          loading: _removeLoading(OwnerSection.paymentMethods),
          paymentMethods: updated,
          actionMessage: queued ? _queuedMessage : null,
          messageSection: queued ? OwnerSection.paymentMethods : null,
        ),
      );
    } catch (e) {
      AppLogger.log(_tag, 'toggle payment method failed', error: e);
      emit(
        state.copyWith(
          loading: _removeLoading(OwnerSection.paymentMethods),
          error: _failure(e, 'Could not update payment method — try again'),
          messageSection: OwnerSection.paymentMethods,
        ),
      );
    }
  }

  Future<void> _onLoadStoreProfile(
    LoadStoreProfileEvent event,
    Emitter<OwnerState> emit,
  ) async {
    try {
      final cachedProfile = ownerRepository.getCachedStoreProfileSync();
      if (cachedProfile != null) {
        emit(state.copyWith(storeProfile: cachedProfile, error: null));
        if (!event.refresh) return;
      } else {
        emit(
          state.copyWith(
            loading: _addLoading(OwnerSection.profile),
            error: null,
          ),
        );
      }
      try {
        final profile = await ownerRepository.getStoreProfile();
        emit(
          state.copyWith(
            loading: _removeLoading(OwnerSection.profile),
            storeProfile: profile,
          ),
        );
      } catch (e) {
        AppLogger.log(_tag, 'load store profile failed', error: e);
        final err = cachedProfile == null
            ? 'Could not load store profile — try again'
            : null;
        emit(
          state.copyWith(
            loading: _removeLoading(OwnerSection.profile),
            error: err,
            messageSection: err != null ? OwnerSection.profile : null,
          ),
        );
      }
    } finally {
      if (event.done != null && !event.done!.isCompleted) {
        event.done!.complete();
      }
    }
  }

  Future<void> _onUpdateStoreProfile(
    UpdateStoreProfileEvent event,
    Emitter<OwnerState> emit,
  ) async {
    emit(
      state.copyWith(loading: _addLoading(OwnerSection.profile), error: null),
    );
    try {
      final profile = await ownerRepository.updateStoreProfile(
        storeName: event.storeName,
        address: event.address,
        phone: event.phone,
        name: event.name,
        email: event.email,
      );
      emit(
        state.copyWith(
          loading: _removeLoading(OwnerSection.profile),
          storeProfile: profile,
          actionMessage: _writeMessage('Store profile updated'),
          messageSection: OwnerSection.profile,
        ),
      );
    } catch (e) {
      AppLogger.log(_tag, 'update store profile failed', error: e);
      emit(
        state.copyWith(
          loading: _removeLoading(OwnerSection.profile),
          error: _failure(e, 'Could not update store profile — try again'),
          messageSection: OwnerSection.profile,
        ),
      );
    }
  }

  Future<void> _onChangePasswordSubmitted(
    ChangePasswordSubmittedEvent event,
    Emitter<OwnerState> emit,
  ) async {
    emit(
      state.copyWith(loading: _addLoading(OwnerSection.profile), error: null),
    );
    try {
      await ownerRepository.changePassword(
        currentPassword: event.currentPassword,
        newPassword: event.newPassword,
      );
      emit(
        state.copyWith(
          loading: _removeLoading(OwnerSection.profile),
          actionMessage: 'Password changed successfully',
          messageSection: OwnerSection.profile,
        ),
      );
    } catch (e) {
      AppLogger.log(_tag, 'change password failed', error: e);
      emit(
        state.copyWith(
          loading: _removeLoading(OwnerSection.profile),
          // A throttled attempt carries the wait time ("Try again in N
          // seconds"); show it instead of a generic retry prompt.
          error: e is RateLimitException
              ? e.message
              : 'Could not change password — try again',
          messageSection: OwnerSection.profile,
        ),
      );
    }
  }
}
