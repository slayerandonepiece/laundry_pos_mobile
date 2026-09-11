import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:myshop/features/owner/data/owner_repository.dart';

import 'owner_event.dart';
import 'owner_state.dart';

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
    on<LoadPaymentMethodsEvent>(_onLoadPaymentMethods);
    on<TogglePaymentMethodEvent>(_onTogglePaymentMethod);
    on<LoadStoreProfileEvent>(_onLoadStoreProfile);
    on<UpdateStoreProfileEvent>(_onUpdateStoreProfile);
    on<ChangePasswordSubmittedEvent>(_onChangePasswordSubmitted);
  }

  Future<void> _onLoadDashboard(
    LoadDashboardEvent event,
    Emitter<OwnerState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, error: null));
    try {
      final metrics = await ownerRepository.getDashboardMetrics(
        from: event.from,
        to: event.to,
      );
      emit(state.copyWith(isLoading: false, metrics: metrics));
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }

  Future<void> _onLoadExpenses(
    LoadExpensesEvent event,
    Emitter<OwnerState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, error: null));
    try {
      final expenses = await ownerRepository.listExpenses();
      emit(state.copyWith(isLoading: false, expenses: expenses));
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
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
      emit(state.copyWith(isLoading: false, error: e.toString()));
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
      emit(state.copyWith(error: e.toString()));
    }
  }

  Future<void> _onLoadStaff(
    LoadStaffEvent event,
    Emitter<OwnerState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, error: null));
    try {
      final staff = await ownerRepository.listStaff();
      emit(state.copyWith(isLoading: false, staff: staff));
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
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
      emit(state.copyWith(isLoading: false, error: e.toString()));
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
      emit(state.copyWith(error: e.toString()));
    }
  }

  Future<void> _onLoadPaymentMethods(
    LoadPaymentMethodsEvent event,
    Emitter<OwnerState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, error: null));
    try {
      final methods = await ownerRepository.listPaymentMethods();
      emit(state.copyWith(isLoading: false, paymentMethods: methods));
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
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
      emit(state.copyWith(error: e.toString()));
    }
  }

  Future<void> _onLoadStoreProfile(
    LoadStoreProfileEvent event,
    Emitter<OwnerState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, error: null));
    try {
      final profile = await ownerRepository.getStoreProfile();
      emit(state.copyWith(isLoading: false, storeProfile: profile));
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
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
      );
      emit(
        state.copyWith(
          isLoading: false,
          storeProfile: profile,
          actionMessage: 'Store profile updated',
        ),
      );
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
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
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }
}
