import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/text_styles.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../shared/widgets/centred_dialog.dart';
import '../bloc/owner_bloc.dart';
import '../bloc/owner_event.dart';
import '../data/models/expense_model.dart';

/// One step to mark a bill paid: the date defaults to today (tap to change),
/// and a monthly bill whose amount varies asks for this month's real amount.
Future<void> showMarkPaidDialog(BuildContext context, Expense expense) async {
  final bloc = context.read<OwnerBloc>();
  final result = await CentredDialog.show<({String paidDate, int? amount})>(
    context: context,
    child: _MarkPaidDialog(expense: expense),
  );
  if (result == null) return;
  bloc.add(
    MarkExpensePaidEvent(
      expense.id,
      paidDate: result.paidDate,
      amount: result.amount,
    ),
  );
}

class _MarkPaidDialog extends StatefulWidget {
  final Expense expense;

  const _MarkPaidDialog({required this.expense});

  @override
  State<_MarkPaidDialog> createState() => _MarkPaidDialogState();
}

class _MarkPaidDialogState extends State<_MarkPaidDialog> {
  late DateTime _date;
  late final TextEditingController _amount;
  String? _error;

  bool get _asksAmount => widget.expense.monthly && !widget.expense.fixed;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _date = DateTime(now.year, now.month, now.day);
    final paise = widget.expense.amount;
    _amount = TextEditingController(
      text: paise % 100 == 0
          ? (paise ~/ 100).toString()
          : (paise / 100).toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(today.year - 1, today.month, today.day),
      lastDate: DateTime(today.year, today.month, today.day),
      helpText: 'Select payment date',
    );
    if (picked != null) setState(() => _date = picked);
  }

  void _confirm() {
    int? paise;
    if (_asksAmount) {
      paise = ((double.tryParse(_amount.text.trim()) ?? 0) * 100).round();
      if (paise <= 0) {
        setState(() => _error = 'Enter this month\'s amount.');
        return;
      }
    }
    Navigator.pop(context, (
      paidDate: DateFormatter.toIsoDateString(_date),
      amount: paise,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return CentredDialog(
      title: widget.expense.title,
      confirmLabel: 'Mark paid',
      onConfirm: _confirm,
      onCancel: () => Navigator.pop(context),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_asksAmount) ...[
            TextField(
              key: const Key('mark_paid_amount'),
              controller: _amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'THIS MONTH\'S AMOUNT (₹)',
                labelStyle: AppTextStyles.fieldLabel,
                errorText: _error,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],
          InkWell(
            key: const Key('mark_paid_date'),
            onTap: _pickDate,
            borderRadius: BorderRadius.circular(10),
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: 'PAID ON',
                labelStyle: AppTextStyles.fieldLabel,
                suffixIcon: const Icon(Icons.calendar_today, size: 18),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(DateFormatter.formatShort(_date)),
            ),
          ),
        ],
      ),
    );
  }
}
