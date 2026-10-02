import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/sync/connectivity_service.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/centred_dialog.dart';
import '../../../shared/widgets/money_text.dart';
import '../../../shared/widgets/status_pill.dart';
import '../../shell/bloc/outlet_scope_cubit.dart';
import '../bloc/owner_bloc.dart';
import '../bloc/owner_event.dart';
import '../bloc/owner_state.dart';
import '../data/models/expense_model.dart';
import 'edit_expense_screen.dart';

class ExpenseDetailScreen extends StatefulWidget {
  final Expense expense;

  const ExpenseDetailScreen({super.key, required this.expense});

  @override
  State<ExpenseDetailScreen> createState() => _ExpenseDetailScreenState();
}

class _ExpenseDetailScreenState extends State<ExpenseDetailScreen> {
  late Expense _expense;

  @override
  void initState() {
    super.initState();
    _expense = widget.expense;
  }

  Future<void> _handleMarkPaid() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final oneYearAgo = DateTime(today.year - 1, today.month, today.day);

    final picked = await showDatePicker(
      context: context,
      initialDate: today,
      firstDate: oneYearAgo,
      lastDate: today,
      helpText: 'Select payment date',
      confirmText: 'Mark paid',
    );

    if (picked != null && mounted) {
      final paidDateStr = DateFormatter.toIsoDateString(picked);
      context.read<OwnerBloc>().add(
        MarkExpensePaidEvent(_expense.id, paidDate: paidDateStr),
      );
    }
  }

  void _openEdit(BuildContext context) async {
    final bloc = context.read<OwnerBloc>();
    final outletCubit = context.read<OutletScopeCubit?>();

    // The edit screen only closes once the server accepted the change; the
    // refreshed expenses list then updates this screen through the listener.
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => MultiBlocProvider(
          providers: [
            BlocProvider<OwnerBloc>.value(value: bloc),
            if (outletCubit != null)
              BlocProvider<OutletScopeCubit>.value(value: outletCubit),
          ],
          child: EditExpenseScreen(expense: _expense),
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    final isMonthly = _expense.monthly;
    final subtitle = isMonthly
        ? 'Delete "${_expense.title}" (${CurrencyFormatter.format(_expense.amount)})?\n\nThis also stops future monthly bills for this expense.'
        : 'Delete "${_expense.title}" (${CurrencyFormatter.format(_expense.amount)})?';

    showDialog(
      context: context,
      builder: (dialogCtx) => CentredDialog(
        title: 'Delete expense?',
        subtitle: subtitle,
        confirmLabel: 'Delete',
        isDestructive: true,
        onConfirm: () {
          context.read<OwnerBloc>().add(DeleteExpenseEvent(_expense.id));
          Navigator.pop(dialogCtx);
          Navigator.pop(context);
        },
        cancelLabel: 'Cancel',
        onCancel: () => Navigator.pop(dialogCtx),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final outletScope = context.watch<OutletScopeCubit?>()?.state;
    final isOffline = ConnectivityService.instance.isOffline;
    final isUnsynced = _expense.isUnsynced;
    final cannotChange = isOffline || isUnsynced;

    final String attributionText;
    if (_expense.outletId == null || _expense.outletId!.isEmpty) {
      attributionText = 'Organization-wide';
    } else {
      final outlet = outletScope?.allowed
          .where((o) => o.id == _expense.outletId)
          .firstOrNull;
      attributionText = outlet?.displayName ?? _expense.outletId!;
    }

    return BlocListener<OwnerBloc, OwnerState>(
      listenWhen: (prev, curr) => prev.expenses != curr.expenses,
      listener: (context, state) {
        final found = state.expenses
            .where((e) => e.id == _expense.id)
            .firstOrNull;
        if (found != null && mounted) {
          setState(() {
            _expense = found;
          });
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(
          backgroundColor: AppColors.surface,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.text),
            onPressed: () => Navigator.pop(context),
          ),
          titleSpacing: 0,
          title: const Text(
            'Expense details',
            style: TextStyle(
              fontFamily: AppTextStyles.fontDisplay,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
              color: AppColors.text,
            ),
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(color: AppColors.border, height: 1),
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppCard(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            _expense.title,
                            style: const TextStyle(
                              fontFamily: AppTextStyles.fontDisplay,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: AppColors.text,
                            ),
                          ),
                        ),
                        if (_expense.monthly) ...[
                          const SizedBox(width: 8),
                          const StatusPill(
                            label: 'Monthly',
                            variant: PillVariant.inProgress,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 12),
                    MoneyText(_expense.amount, fontSize: 28),
                    const SizedBox(height: 16),
                    const Divider(color: AppColors.border, height: 1),
                    const SizedBox(height: 16),
                    _buildDetailRow('Category', _expense.category),
                    const SizedBox(height: 12),
                    _buildDetailRow('Due date', _expense.due),
                    const SizedBox(height: 12),
                    _buildDetailRow(
                      'Payment status',
                      _expense.isPaid ? 'Paid (${_expense.paid})' : 'Unpaid',
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_expense.isPaid && _expense.paid != null) ...[
                            Text(
                              'Paid (${_expense.paid})',
                              style: const TextStyle(
                                fontFamily: AppTextStyles.fontBody,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.success,
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          StatusPill(
                            label: _expense.isPaid ? 'Paid' : 'Unpaid',
                            variant: _expense.isPaid
                                ? PillVariant.paid
                                : PillVariant.warning,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildDetailRow('Applies to', attributionText),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              if (!_expense.isPaid) ...[
                PrimaryButton(
                  label: 'Mark as paid',
                  onPressed: _handleMarkPaid,
                ),
                const SizedBox(height: 14),
              ],
              Row(
                children: [
                  Expanded(
                    child: SecondaryButton(
                      label: 'Edit',
                      onPressed: cannotChange ? null : () => _openEdit(context),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SecondaryButton(
                      label: 'Delete',
                      textColor: cannotChange ? null : AppColors.danger,
                      borderColor: cannotChange
                          ? null
                          : AppColors.danger.withValues(alpha: 0.3),
                      onPressed: cannotChange
                          ? null
                          : () => _confirmDelete(context),
                    ),
                  ),
                ],
              ),
              if (cannotChange) ...[
                const SizedBox(height: 10),
                Center(
                  child: Text(
                    isUnsynced
                        ? 'Still syncing — available once saved'
                        : 'Needs a connection',
                    style: const TextStyle(
                      fontFamily: AppTextStyles.fontBody,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.danger,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {Widget? trailing}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontFamily: AppTextStyles.fontBody,
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppColors.mutedText,
          ),
        ),
        trailing ??
            Text(
              value,
              style: const TextStyle(
                fontFamily: AppTextStyles.fontBody,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              ),
            ),
      ],
    );
  }
}
