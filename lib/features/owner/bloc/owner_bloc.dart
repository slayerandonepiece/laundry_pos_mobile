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
    on<AddPaymentMethodEvent>(_onAddPaymentMethod);
    on<RenamePaymentMethodEvent>(_onRenamePaymentMethod);
    on<LoadStoreProfileEvent>(_onLoadStoreProfile);
    on<UpdateStoreProfileEvent>(_onUpdateStoreProfile);
    on<ChangePasswordSubmittedEvent>(_onChangePasswordSubmitted);
  }

  Future<void> _onLoadDashboard(
    LoadDashboardEvent event,
    Emitter<OwnerState> emit,
  ) async {
    // Render whatever is cached immediately (no spinner) so charts don't sit
    // blank while the network round-trip is in flight, then let the network
    // fetch below silently replace it once it resolves.
    final cachedMetrics = ownerRepository.getCachedDashboardMetricsSync();
    if (cachedMetrics != null) {
      emit(state.copyWith(metrics: cachedMetrics, error: null));
    } else {
      emit(state.copyWith(isLoading: true, error: null));
    }
    try {
      final metrics = await ownerRepository.getDashboardMetrics(
        from: event.from,
        to: event.to,
      );
      emit(state.copyWith(isLoading: false, metrics: metrics));
    } catch (e) {
      AppLogger.log(_tag, 'load dashboard failed', error: e);
      emit(
        state.copyWith(
          isLoading: false,
          error: cachedMetrics == null
              ? 'Could not load dashboard — try again'
              : null,
        ),
      );
    }
  }

  Future<void> _onLoadExpenses(
    LoadExpensesEvent event,
    Emitter<OwnerState> emit,
  ) async {
    final cachedExpenses = ownerRepository.getCachedExpensesSync();
    if (cachedExpenses != null) {
      emit(state.copyWith(expenses: cachedExpenses, error: null));
    } else {
      emit(state.copyWith(isLoading: true, error: null));
    }
    try {
      final expenses = await ownerRepository.listExpenses();
      emit(state.copyWith(isLoading: false, expenses: expenses));
    } catch (e) {
      AppLogger.log(_tag, 'load expenses failed', error: e);
      emit(
        state.copyWith(
          isLoading: false,
          error: cachedExpenses == null
              ? 'Could not load expenses — try again'
              : null,
        ),
      );
    }
  }

  Future<void> _onAddExpense(
    AddExpenseEvent event,
    Emitter<OwnerState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, error: null));
    try {
      await ownerRepository.createExpense(
        title: event.title,
        category: event.category,
        amount: event.amount,
        due: event.due,
        monthly: event.monthly,
      );
      final updated = await ownerRepository.listExpenses();
      emit(
        state.copyWith(
          isLoading: false,
          expenses: updated,
          actionMessage: 'Expense recorded successfully',
        ),
      );
    } catch (e) {
      AppLogger.log(_tag, 'add expense failed', error: e);
      emit(
        state.copyWith(
          isLoading: false,
          error: 'Could not add expense — try again',
        ),
      );
    }
  }

  Future<void> _onMarkExpensePaid(
    MarkExpensePaidEvent event,
    Emitter<OwnerState> emit,
  ) async {
    try {
      await ownerRepository.markExpensePaid(event.expenseId);
      final updated = await ownerRepository.listExpenses();
      emit(
        state.copyWith(expenses: updated, actionMessage: 'Expense marked paid'),
      );
    } catch (e) {
      AppLogger.log(_tag, 'mark expense paid failed', error: e);
      emit(state.copyWith(error: 'Could not mark expense paid — try again'));
    }
  }

  Future<void> _onLoadStaff(
    LoadStaffEvent event,
    Emitter<OwnerState> emit,
  ) async {
    final cachedStaff = ownerRepository.getCachedStaffSync();
    if (cachedStaff != null) {
      emit(state.copyWith(staff: cachedStaff, error: null));
    } else {
      emit(state.copyWith(isLoading: true, error: null));
    }
    try {
      final staff = await ownerRepository.listStaff();
      emit(state.copyWith(isLoading: false, staff: staff));
    } catch (e) {
      AppLogger.log(_tag, 'load staff failed', error: e);
      emit(
        state.copyWith(
          isLoading: false,
          error: cachedStaff == null
              ? 'Could not load staff — try again'
              : null,
        ),
      );
    }
  }

  Future<void> _onAddStaff(
    AddStaffEvent event,
    Emitter<OwnerState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, error: null));
    try {
      await ownerRepository.createStaff(
        name: event.name,
        username: event.username,
        password: event.password,
      );
      final updated = await ownerRepository.listStaff();
      emit(
        state.copyWith(
          isLoading: false,
          staff: updated,
          actionMessage: 'Staff member added successfully',
        ),
      );
    } catch (e) {
      AppLogger.log(_tag, 'add staff failed', error: e);
      emit(
        state.copyWith(
          isLoading: false,
          error: 'Could not add staff — try again',
        ),
      );
    }
  }

  Future<void> _onToggleStaffActive(
    ToggleStaffActiveEvent event,
    Emitter<OwnerState> emit,
  ) async {
    try {
      await ownerRepository.toggleStaffActive(event.employeeId);
      final updated = await ownerRepository.listStaff();
      emit(state.copyWith(staff: updated));
    } catch (e) {
      AppLogger.log(_tag, 'toggle staff active failed', error: e);
      emit(state.copyWith(error: 'Could not update staff status — try again'));
    }
  }

  Future<void> _onUpdateStaff(
    UpdateStaffEvent event,
    Emitter<OwnerState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, error: null));
    try {
      await ownerRepository.updateStaff(
        employeeId: event.employeeId,
        name: event.name,
        username: event.username,
      );
      final updated = await ownerRepository.listStaff();
      emit(
        state.copyWith(
          isLoading: false,
          staff: updated,
          actionMessage: 'Staff member updated successfully',
        ),
      );
    } catch (e) {
      AppLogger.log(_tag, 'update staff failed', error: e);
      emit(
        state.copyWith(
          isLoading: false,
          error: 'Could not update staff — try again',
        ),
      );
    }
  }

  Future<void> _onLoadPaymentMethods(
    LoadPaymentMethodsEvent event,
    Emitter<OwnerState> emit,
  ) async {
    final cachedMethods = ownerRepository.getCachedPaymentMethodsSync();
    if (cachedMethods != null) {
      emit(state.copyWith(paymentMethods: cachedMethods, error: null));
    } else {
      emit(state.copyWith(isLoading: true, error: null));
    }
    try {
      final methods = await ownerRepository.listPaymentMethods();
      emit(state.copyWith(isLoading: false, paymentMethods: methods));
    } catch (e) {
      AppLogger.log(_tag, 'load payment methods failed', error: e);
      emit(
        state.copyWith(
          isLoading: false,
          error: cachedMethods == null
              ? 'Could not load payment methods — try again'
              : null,
        ),
      );
    }
  }

  Future<void> _onTogglePaymentMethod(
    TogglePaymentMethodEvent event,
    Emitter<OwnerState> emit,
  ) async {
    try {
      await ownerRepository.togglePaymentMethod(event.id, event.active);
      final updated = await ownerRepository.listPaymentMethods();
      emit(state.copyWith(paymentMethods: updated));
    } catch (e) {
      AppLogger.log(_tag, 'toggle payment method failed', error: e);
      emit(
        state.copyWith(error: 'Could not update payment method — try again'),
      );
    }
  }

  Future<void> _onAddPaymentMethod(
    AddPaymentMethodEvent event,
    Emitter<OwnerState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, error: null));
    try {
      await ownerRepository.createPaymentMethod(name: event.name);
      final updated = await ownerRepository.listPaymentMethods();
      emit(
        state.copyWith(
          isLoading: false,
          paymentMethods: updated,
          actionMessage: 'Payment method added',
        ),
      );
    } catch (e) {
      AppLogger.log(_tag, 'add payment method failed', error: e);
      emit(
        state.copyWith(
          isLoading: false,
          error: 'Could not add payment method — try again',
        ),
      );
    }
  }

  Future<void> _onRenamePaymentMethod(
    RenamePaymentMethodEvent event,
    Emitter<OwnerState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, error: null));
    try {
      await ownerRepository.renamePaymentMethod(id: event.id, name: event.name);
      final updated = await ownerRepository.listPaymentMethods();
      emit(
        state.copyWith(
          isLoading: false,
          paymentMethods: updated,
          actionMessage: 'Payment method renamed',
        ),
      );
    } catch (e) {
      AppLogger.log(_tag, 'rename payment method failed', error: e);
      emit(
        state.copyWith(
          isLoading: false,
          error: 'Could not rename payment method — try again',
        ),
      );
    }
  }

  Future<void> _onLoadStoreProfile(
    LoadStoreProfileEvent event,
    Emitter<OwnerState> emit,
  ) async {
    final cachedProfile = ownerRepository.getCachedStoreProfileSync();
    if (cachedProfile != null) {
      emit(state.copyWith(storeProfile: cachedProfile, error: null));
    } else {
      emit(state.copyWith(isLoading: true, error: null));
    }
    try {
      final profile = await ownerRepository.getStoreProfile();
      emit(state.copyWith(isLoading: false, storeProfile: profile));
    } catch (e) {
      AppLogger.log(_tag, 'load store profile failed', error: e);
      emit(
        state.copyWith(
          isLoading: false,
          error: cachedProfile == null
              ? 'Could not load store profile — try again'
              : null,
        ),
      );
    }
  }

  Future<void> _onUpdateStoreProfile(
    UpdateStoreProfileEvent event,
    Emitter<OwnerState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, error: null));
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
          isLoading: false,
          storeProfile: profile,
          actionMessage: 'Store profile updated',
        ),
      );
    } catch (e) {
      AppLogger.log(_tag, 'update store profile failed', error: e);
      emit(
        state.copyWith(
          isLoading: false,
          error: 'Could not update store profile — try again',
        ),
      );
    }
  }

  Future<void> _onChangePasswordSubmitted(
    ChangePasswordSubmittedEvent event,
    Emitter<OwnerState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, error: null));
    try {
      await ownerRepository.changePassword(
        currentPassword: event.currentPassword,
        newPassword: event.newPassword,
      );
      emit(
        state.copyWith(
          isLoading: false,
          actionMessage: 'Password changed successfully',
        ),
      );
    } catch (e) {
      AppLogger.log(_tag, 'change password failed', error: e);
      emit(
        state.copyWith(
          isLoading: false,
          error: 'Could not change password — try again',
        ),
      );
    }
  }
}
