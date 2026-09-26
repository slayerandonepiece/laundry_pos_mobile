import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:myshop/core/logging/app_logger.dart';
import 'package:myshop/features/owner/data/owner_repository.dart';

import 'owner_event.dart';
import 'owner_state.dart';

const _tag = 'OWNER_BLOC';

class OwnerBloc extends Bloc<OwnerEvent, OwnerState> {
  final OwnerRepository ownerRepository;

  OwnerBloc({required this.ownerRepository}) : super(OwnerState()) {
    on<LoadDashboardEvent>(_onLoadDashboard);
    on<LoadExpensesEvent>(_onLoadExpenses);
    on<AddExpenseEvent>(_onAddExpense);
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
    try {
      // Opening the screen shows the cache only; the network is used on
      // refresh, for a custom date range (only the default period is cached),
      // or when nothing is cached yet.
      final isCustomRange = event.from != null || event.to != null;
      final cachedMetrics = isCustomRange
          ? null
          : ownerRepository.getCachedDashboardMetricsSync();
      if (cachedMetrics != null) {
        emit(state.copyWith(metrics: cachedMetrics, error: null));
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
        );
        emit(
          state.copyWith(
            loading: _removeLoading(OwnerSection.dashboard),
            metrics: metrics,
          ),
        );
      } catch (e) {
        AppLogger.log(_tag, 'load dashboard failed', error: e);
        final err = cachedMetrics == null
            ? 'Could not load dashboard — try again'
            : null;
        emit(
          state.copyWith(
            loading: _removeLoading(OwnerSection.dashboard),
            error: err,
            messageSection: err != null ? OwnerSection.dashboard : null,
          ),
        );
      }
    } finally {
      if (event.done != null && !event.done!.isCompleted) {
        event.done!.complete();
      }
    }
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
      state.copyWith(
        loading: _addLoading(OwnerSection.expenses),
        error: null,
      ),
    );
    try {
      await ownerRepository.createExpense(
        title: event.title,
        category: event.category,
        amount: event.amount,
        due: event.due,
        monthly: event.monthly,
        idempotencyKey: event.idempotencyKey,
      );
      final updated = await ownerRepository.listExpenses();
      emit(
        state.copyWith(
          loading: _removeLoading(OwnerSection.expenses),
          expenses: updated,
          actionMessage: 'Expense recorded successfully',
          messageSection: OwnerSection.expenses,
        ),
      );
    } catch (e) {
      AppLogger.log(_tag, 'add expense failed', error: e);
      emit(
        state.copyWith(
          loading: _removeLoading(OwnerSection.expenses),
          error: 'Could not add expense — try again',
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
      state.copyWith(
        loading: _addLoading(OwnerSection.expenses),
        error: null,
      ),
    );
    try {
      await ownerRepository.markExpensePaid(event.expenseId);
      final updated = await ownerRepository.listExpenses();
      emit(
        state.copyWith(
          loading: _removeLoading(OwnerSection.expenses),
          expenses: updated,
          actionMessage: 'Expense marked paid',
          messageSection: OwnerSection.expenses,
        ),
      );
    } catch (e) {
      AppLogger.log(_tag, 'mark expense paid failed', error: e);
      emit(
        state.copyWith(
          loading: _removeLoading(OwnerSection.expenses),
          error: 'Could not mark expense paid — try again',
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
        if (!event.refresh) return;
      } else {
        emit(
          state.copyWith(
            loading: _addLoading(OwnerSection.staff),
            error: null,
          ),
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
    emit(
      state.copyWith(
        loading: _addLoading(OwnerSection.staff),
        error: null,
      ),
    );
    try {
      await ownerRepository.createStaff(
        name: event.name,
        username: event.username,
        password: event.password,
        idempotencyKey: event.idempotencyKey,
      );
      final updated = await ownerRepository.listStaff();
      emit(
        state.copyWith(
          loading: _removeLoading(OwnerSection.staff),
          staff: updated,
          actionMessage: 'Staff member added successfully',
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
              : 'Could not add staff — try again',
          messageSection: OwnerSection.staff,
        ),
      );
    }
  }

  Future<void> _onToggleStaffActive(
    ToggleStaffActiveEvent event,
    Emitter<OwnerState> emit,
  ) async {
    emit(
      state.copyWith(
        loading: _addLoading(OwnerSection.staff),
        error: null,
      ),
    );
    try {
      await ownerRepository.toggleStaffActive(event.employeeId);
      final updated = await ownerRepository.listStaff();
      emit(
        state.copyWith(
          loading: _removeLoading(OwnerSection.staff),
          staff: updated,
        ),
      );
    } catch (e) {
      AppLogger.log(_tag, 'toggle staff active failed', error: e);
      emit(
        state.copyWith(
          loading: _removeLoading(OwnerSection.staff),
          error: 'Could not update staff status — try again',
          messageSection: OwnerSection.staff,
        ),
      );
    }
  }

  Future<void> _onUpdateStaff(
    UpdateStaffEvent event,
    Emitter<OwnerState> emit,
  ) async {
    emit(
      state.copyWith(
        loading: _addLoading(OwnerSection.staff),
        error: null,
      ),
    );
    try {
      await ownerRepository.updateStaff(
        employeeId: event.employeeId,
        name: event.name,
        username: event.username,
      );
      final updated = await ownerRepository.listStaff();
      emit(
        state.copyWith(
          loading: _removeLoading(OwnerSection.staff),
          staff: updated,
          actionMessage: 'Staff member updated successfully',
          messageSection: OwnerSection.staff,
        ),
      );
    } catch (e) {
      AppLogger.log(_tag, 'update staff failed', error: e);
      emit(
        state.copyWith(
          loading: _removeLoading(OwnerSection.staff),
          error: 'Could not update staff — try again',
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
      final updated = await ownerRepository.listPaymentMethods();
      emit(
        state.copyWith(
          loading: _removeLoading(OwnerSection.paymentMethods),
          paymentMethods: updated,
        ),
      );
    } catch (e) {
      AppLogger.log(_tag, 'toggle payment method failed', error: e);
      emit(
        state.copyWith(
          loading: _removeLoading(OwnerSection.paymentMethods),
          error: 'Could not update payment method — try again',
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
      state.copyWith(
        loading: _addLoading(OwnerSection.profile),
        error: null,
      ),
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
          actionMessage: 'Store profile updated',
          messageSection: OwnerSection.profile,
        ),
      );
    } catch (e) {
      AppLogger.log(_tag, 'update store profile failed', error: e);
      emit(
        state.copyWith(
          loading: _removeLoading(OwnerSection.profile),
          error: 'Could not update store profile — try again',
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
      state.copyWith(
        loading: _addLoading(OwnerSection.profile),
        error: null,
      ),
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
          error: 'Could not change password — try again',
          messageSection: OwnerSection.profile,
        ),
      );
    }
  }
}
