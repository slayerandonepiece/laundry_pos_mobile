import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:myshop/core/constants/app_colors.dart';
import 'package:myshop/core/theme/text_styles.dart';
import 'package:myshop/core/utils/currency_formatter.dart';
import 'package:myshop/features/owner/bloc/owner_bloc.dart';
import 'package:myshop/features/owner/bloc/owner_event.dart';
import 'package:myshop/features/owner/bloc/owner_state.dart';
import 'package:myshop/features/owner/data/models/expense_model.dart';
import 'package:myshop/shared/widgets/app_button.dart';
import 'package:myshop/shared/widgets/app_card.dart';
import 'package:myshop/shared/widgets/app_text_field.dart';
import 'package:myshop/shared/widgets/centred_dialog.dart';
import 'package:myshop/shared/widgets/empty_state.dart';
import 'package:myshop/shared/widgets/filter_chip.dart';
import 'package:myshop/shared/widgets/status_pill.dart';

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  String _activeFilter = 'all'; // 'all' | 'unpaid' | 'recurring'

  @override
  void initState() {
    super.initState();
    context.read<OwnerBloc>().add(LoadExpensesEvent());
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<OwnerBloc, OwnerState>(
      listener: (context, state) {
        if (state.actionMessage != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.actionMessage!),
              backgroundColor: AppColors.success,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      },
      builder: (context, state) {
        final expenses = state.expenses;
        final totalAmount = expenses.fold(0, (sum, e) => sum + e.amount);

        final filtered = expenses.where((e) {
          if (_activeFilter == 'unpaid') return !e.isPaid;
          if (_activeFilter == 'recurring') return e.monthly;
          return true;
        }).toList();

        final unpaidCount = expenses.where((e) => !e.isPaid).length;

        return Scaffold(
          backgroundColor: AppColors.surface,
          appBar: AppBar(
            backgroundColor: AppColors.surface,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: AppColors.text),
              onPressed: () => Navigator.pop(context),
            ),
            titleSpacing: 0,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Expenses',
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontDisplay,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Total ${CurrencyFormatter.format(totalAmount)}',
                  style: AppTextStyles.hint,
                ),
              ],
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: IconButton(
                  icon: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: const Icon(Icons.add, color: Colors.white, size: 20),
                  ),
                  onPressed: () => _showAddExpenseDialog(context),
                ),
              ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Container(color: AppColors.border, height: 1),
            ),
          ),
          body: RefreshIndicator(
            onRefresh: () async {
              context.read<OwnerBloc>().add(LoadExpensesEvent());
            },
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // Filter chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      AppFilterChip(
                        label: 'All',
                        isSelected: _activeFilter == 'all',
                        onTap: () => setState(() => _activeFilter = 'all'),
                      ),
                      const SizedBox(width: 8),
                      AppFilterChip(
                        label: 'Unpaid $unpaidCount',
                        isSelected: _activeFilter == 'unpaid',
                        onTap: () => setState(() => _activeFilter = 'unpaid'),
                      ),
                      const SizedBox(width: 8),
                      AppFilterChip(
                        label: 'Recurring',
                        isSelected: _activeFilter == 'recurring',
                        onTap: () =>
                            setState(() => _activeFilter = 'recurring'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                if (filtered.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 40),
                    child: EmptyState(
                      icon: Icons.receipt_long_outlined,
                      title: 'No expenses found',
                      subtitle: 'Add an expense using the + button above.',
                    ),
                  )
                else
                  ...filtered.map((expense) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 11),
                      child: AppCard(
                        padding: const EdgeInsets.all(14),
                        onTap: !expense.isPaid
                            ? () => _showMarkPaidDialog(context, expense)
                            : null,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        expense.title,
                                        style: const TextStyle(
                                          fontFamily: AppTextStyles.fontBody,
                                          fontSize: 14.5,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.text,
                                        ),
                                      ),
                                      if (expense.monthly) ...[
                                        const SizedBox(width: 7),
                                        const StatusPill(
                                          label: 'Monthly',
                                          variant: PillVariant.inProgress,
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${expense.category} · Due ${expense.due}',
                                    style: AppTextStyles.hint,
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  CurrencyFormatter.format(expense.amount),
                                  style: const TextStyle(
                                    fontFamily: AppTextStyles.fontDisplay,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.text,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                StatusPill(
                                  label: expense.isPaid ? 'Paid' : 'Unpaid',
                                  variant: expense.isPaid
                                      ? PillVariant.paid
                                      : PillVariant.ready,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showMarkPaidDialog(BuildContext context, Expense expense) {
    showDialog(
      context: context,
      builder: (_) => CentredDialog(
        title: 'Mark expense paid?',
        subtitle:
            'Mark "${expense.title}" (${CurrencyFormatter.format(expense.amount)}) as paid?',
        confirmLabel: 'Mark paid',
        onConfirm: () {
          context.read<OwnerBloc>().add(MarkExpensePaidEvent(expense.id));
          Navigator.pop(context);
        },
        cancelLabel: 'Cancel',
        onCancel: () => Navigator.pop(context),
      ),
    );
  }

  void _showAddExpenseDialog(BuildContext context) {
    final titleController = TextEditingController();
    final amountController = TextEditingController();
    String category = 'Operations';
    bool monthly = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return Container(
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 10,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: AppColors.controlBorder,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const Text(
                  'Add expense',
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontDisplay,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 16),
                AppTextField(
                  label: 'TITLE',
                  hint: 'e.g. Shop rent, Electricity, Detergent',
                  controller: titleController,
                ),
                const SizedBox(height: 12),
                AppTextField(
                  label: 'AMOUNT (₹)',
                  hint: 'e.g. 5000',
                  keyboardType: TextInputType.number,
                  controller: amountController,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: category,
                        decoration: InputDecoration(
                          labelText: 'CATEGORY',
                          labelStyle: AppTextStyles.fieldLabel,
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
                                .map(
                                  (c) => DropdownMenuItem(
                                    value: c,
                                    child: Text(c),
                                  ),
                                )
                                .toList(),
                        onChanged: (v) =>
                            setDialogState(() => category = v ?? 'Operations'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Recurring monthly expense',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  value: monthly,
                  activeThumbColor: AppColors.primary,
                  onChanged: (v) => setDialogState(() => monthly = v),
                ),
                const SizedBox(height: 18),
                PrimaryButton(
                  label: 'Save expense',
                  onPressed: () {
                    final title = titleController.text.trim();
                    final amountInRupees =
                        double.tryParse(amountController.text.trim()) ?? 0;
                    final amountInPaise = (amountInRupees * 100).round();
                    if (title.isEmpty || amountInPaise <= 0) return;

                    final now = DateTime.now();
                    final due =
                        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

                    context.read<OwnerBloc>().add(
                      AddExpenseEvent(
                        title: title,
                        category: category,
                        amount: amountInPaise,
                        due: due,
                        monthly: monthly,
                      ),
                    );
                    Navigator.pop(sheetContext);
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
