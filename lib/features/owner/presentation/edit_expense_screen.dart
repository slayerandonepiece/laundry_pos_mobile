import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../shell/bloc/outlet_scope_cubit.dart';
import '../bloc/owner_bloc.dart';
import '../bloc/owner_event.dart';
import '../bloc/owner_state.dart';
import '../data/models/expense_model.dart';

class EditExpenseScreen extends StatefulWidget {
  final Expense expense;

  const EditExpenseScreen({super.key, required this.expense});

  @override
  State<EditExpenseScreen> createState() => _EditExpenseScreenState();
}

class _EditExpenseScreenState extends State<EditExpenseScreen> {
  late final TextEditingController _titleController;
  late final TextEditingController _amountController;
  late String _category;
  late String _due;
  late String? _selectedOutletId;
  String? _errorMessage;
  bool _submitting = false;
  bool _sawLoading = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.expense.title);
    final rupees = widget.expense.amount / 100;
    _amountController = TextEditingController(
      text: widget.expense.amount % 100 == 0
          ? rupees.toInt().toString()
          : rupees.toStringAsFixed(2),
    );
    _category = widget.expense.category;
    _due = widget.expense.due;
    _selectedOutletId = widget.expense.outletId;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _pickDueDate() async {
    final orig =
        DateFormatter.parseCalendarDate(widget.expense.due) ?? DateTime.now();
    final current = DateFormatter.parseCalendarDate(_due) ?? orig;

    DateTime firstDate;
    DateTime lastDate;
    if (widget.expense.monthly) {
      // Backend constraint: recurring occurrence cannot move to another month
      firstDate = DateTime(orig.year, orig.month, 1);
      lastDate = DateTime(orig.year, orig.month + 1, 0);
    } else {
      firstDate = DateTime(orig.year - 5, 1, 1);
      lastDate = DateTime(orig.year + 5, 12, 31);
    }

    final initial = current.isBefore(firstDate)
        ? firstDate
        : (current.isAfter(lastDate) ? lastDate : current);

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: firstDate,
      lastDate: lastDate,
      helpText: widget.expense.monthly
          ? 'Select due date within month'
          : 'Select due date',
    );

    if (picked != null && mounted) {
      setState(() {
        _due = DateFormatter.toIsoDateString(picked);
      });
    }
  }

  void _handleSave() {
    final title = _titleController.text.trim();
    final amountInRupees = double.tryParse(_amountController.text.trim()) ?? 0;
    final amountInPaise = (amountInRupees * 100).round();
    if (title.isEmpty || amountInPaise <= 0) {
      setState(() {
        _errorMessage = 'Please enter a valid title and amount.';
      });
      return;
    }

    setState(() {
      _submitting = true;
      _sawLoading = false;
      _errorMessage = null;
    });
    context.read<OwnerBloc>().add(
      UpdateExpenseEvent(
        expenseId: widget.expense.id,
        title: title,
        category: _category,
        amount: amountInPaise,
        due: _due,
        outletId: _selectedOutletId,
      ),
    );
  }

  /// Stay on this form until the server has answered: close on success, show
  /// the reason here on failure so nothing unsaved looks saved.
  void _onOwnerState(BuildContext context, OwnerState state) {
    if (!_submitting) return;
    if (state.loading.contains(OwnerSection.expenses)) {
      _sawLoading = true;
      return;
    }
    if (!_sawLoading) return;
    _submitting = false;
    _sawLoading = false;
    if (state.error != null) {
      setState(() => _errorMessage = state.error);
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final outletScope = context.watch<OutletScopeCubit?>()?.state;
    final allowedOutlets = outletScope?.allowed ?? const [];

    final String scopeHint;
    if (_selectedOutletId == null || _selectedOutletId!.isEmpty) {
      scopeHint = 'This expense will be recorded as organization-wide.';
    } else {
      final activeOutlet = allowedOutlets
          .where((o) => o.id == _selectedOutletId)
          .firstOrNull;
      final displayName = activeOutlet?.displayName ?? _selectedOutletId!;
      scopeHint = 'This expense will be recorded against $displayName.';
    }

    return BlocListener<OwnerBloc, OwnerState>(
      listener: _onOwnerState,
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
            'Edit expense',
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
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppTextField(
                label: 'TITLE',
                hint: 'e.g. Shop rent, Electricity, Detergent',
                controller: _titleController,
              ),
              const SizedBox(height: 14),
              AppTextField(
                label: 'AMOUNT (₹)',
                hint: 'e.g. 5000',
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                controller: _amountController,
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: InputDecoration(
                  labelText: 'CATEGORY',
                  labelStyle: AppTextStyles.fieldLabel,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 14,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                items:
                    [
                          'Operations',
                          'Supplies',
                          'Rent',
                          'Utilities',
                          'Maintenance',
                          'Other',
                        ]
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                onChanged: (v) {
                  if (v != null) {
                    setState(() => _category = v);
                  }
                },
              ),
              const SizedBox(height: 14),
              InkWell(
                onTap: _pickDueDate,
                borderRadius: BorderRadius.circular(10),
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'DUE DATE',
                    labelStyle: AppTextStyles.fieldLabel,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 14,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    suffixIcon: const Icon(
                      Icons.calendar_today,
                      size: 18,
                      color: AppColors.mutedText,
                    ),
                  ),
                  child: Text(
                    _due,
                    style: const TextStyle(
                      fontFamily: AppTextStyles.fontBody,
                      fontSize: 14.5,
                      color: AppColors.text,
                    ),
                  ),
                ),
              ),
              if (widget.expense.monthly) ...[
                const SizedBox(height: 6),
                const Text(
                  'Due date for recurring bills is limited to the current month.',
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontBody,
                    fontSize: 11.5,
                    color: AppColors.mutedText,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              // "Applies to" selector (M1.8)
              DropdownButtonFormField<String?>(
                initialValue: _selectedOutletId,
                decoration: InputDecoration(
                  labelText: 'APPLIES TO',
                  labelStyle: AppTextStyles.fieldLabel,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 14,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Organization-wide'),
                  ),
                  ...allowedOutlets.map(
                    (o) => DropdownMenuItem<String?>(
                      value: o.id,
                      child: Text(o.displayName),
                    ),
                  ),
                ],
                onChanged: (v) {
                  setState(() => _selectedOutletId = v);
                },
              ),
              const SizedBox(height: 6),
              Text(scopeHint, style: AppTextStyles.hint),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppColors.inset,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Recurring monthly expense',
                            style: TextStyle(
                              fontFamily: AppTextStyles.fontBody,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.text,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Recurring setting cannot be changed for existing expenses.',
                            style: TextStyle(
                              fontFamily: AppTextStyles.fontBody,
                              fontSize: 11.5,
                              color: AppColors.mutedText,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Switch(
                      value: widget.expense.monthly,
                      activeThumbColor: AppColors.primary,
                      onChanged:
                          null, // Disabled on edit per backend constraint
                    ),
                  ],
                ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorMessage!,
                  style: const TextStyle(
                    fontFamily: AppTextStyles.fontBody,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.danger,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              PrimaryButton(
                label: 'Save expense',
                isLoading: _submitting,
                onPressed: _submitting ? null : _handleSave,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
