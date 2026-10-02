import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:myshop/core/constants/app_colors.dart';
import 'package:myshop/core/sync/sync_engine.dart';
import 'package:myshop/core/theme/text_styles.dart';
import 'package:myshop/core/utils/currency_formatter.dart';
import 'package:myshop/core/utils/date_formatter.dart';
import 'package:myshop/core/utils/idempotency.dart';
import 'package:myshop/features/owner/bloc/owner_bloc.dart';
import 'package:myshop/features/owner/bloc/owner_event.dart';
import 'package:myshop/features/owner/bloc/owner_state.dart';
import 'package:myshop/features/owner/data/models/expense_model.dart';
import 'package:myshop/features/shell/bloc/outlet_scope_cubit.dart';
import 'package:myshop/shared/widgets/app_button.dart';
import 'package:myshop/shared/widgets/app_card.dart';
import 'package:myshop/shared/widgets/app_text_field.dart';
import 'package:myshop/shared/widgets/empty_state.dart';
import 'package:myshop/shared/widgets/filter_chip.dart';
import 'package:myshop/shared/widgets/outlet_title_switcher.dart';
import 'package:myshop/shared/widgets/status_pill.dart';
import 'package:myshop/shared/widgets/sync_status_bar.dart';

import 'expense_detail_screen.dart';

export 'edit_expense_screen.dart';
export 'expense_detail_screen.dart';

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _selectedPeriod =
      '30d'; // 'today' | '7d' | '30d' | 'quarter' | 'custom'
  DateTime? _customFrom;
  DateTime? _customTo;
  String _activeFilter = 'all'; // 'all' | 'unpaid' | 'recurring'
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    context.read<OwnerBloc>().add(LoadExpensesEvent(refresh: true));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  DateTime _startOfDay(DateTime dt) {
    final local = dt.isUtc ? dt.toLocal() : dt;
    return DateTime(local.year, local.month, local.day);
  }

  DateTime? _parseDate(String? dateStr) {
    if (dateStr == null || dateStr.trim().isEmpty) return null;
    return DateFormatter.parseCalendarDate(dateStr) ??
        DateTime.tryParse(dateStr.trim());
  }

  Future<void> _pickCustomDate({required bool isFrom}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom
          ? (_customFrom ?? now)
          : (_customTo ?? _customFrom ?? now),
      firstDate: DateTime(2020),
      lastDate: now,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppColors.primary,
            onPrimary: Colors.white,
            onSurface: AppColors.text,
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _customFrom = picked;
        if (_customTo != null && _customTo!.isBefore(_customFrom!)) {
          _customTo = _customFrom;
        }
      } else {
        _customTo = picked;
        if (_customFrom != null && _customFrom!.isAfter(_customTo!)) {
          _customFrom = _customTo;
        }
      }
    });
  }

  Widget _buildCustomDateSelector() {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.selectedSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => _pickCustomDate(isFrom: true),
              child: Row(
                children: [
                  const Icon(
                    Icons.calendar_today_outlined,
                    size: 14,
                    color: AppColors.mutedText,
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'FROM',
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontBody,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                          color: AppColors.mutedText,
                        ),
                      ),
                      Text(
                        _customFrom != null
                            ? DateFormatter.formatShort(_customFrom!)
                            : 'Pick date',
                        style: const TextStyle(
                          fontFamily: AppTextStyles.fontBody,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Container(width: 1, height: 26, color: AppColors.border),
          const SizedBox(width: 14),
          Expanded(
            child: InkWell(
              onTap: () => _pickCustomDate(isFrom: false),
              child: Row(
                children: [
                  const Icon(
                    Icons.calendar_today_outlined,
                    size: 14,
                    color: AppColors.mutedText,
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'TO',
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontBody,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                          color: AppColors.mutedText,
                        ),
                      ),
                      Text(
                        _customTo != null
                            ? DateFormatter.formatShort(_customTo!)
                            : 'Pick date',
                        style: const TextStyle(
                          fontFamily: AppTextStyles.fontBody,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _matchesPeriod(DateTime targetDate, String period, DateTime todayStart) {
    final d = _startOfDay(targetDate);
    final tomorrowStart = todayStart.add(const Duration(days: 1));

    switch (period) {
      case 'today':
        return d.isAtSameMomentAs(todayStart);
      case '7d':
        final start7d = todayStart.subtract(const Duration(days: 6));
        return !d.isBefore(start7d) && d.isBefore(tomorrowStart);
      case '30d':
        final start30d = todayStart.subtract(const Duration(days: 29));
        final isLast30d = !d.isBefore(start30d) && d.isBefore(tomorrowStart);
        final isThisMonth =
            d.year == todayStart.year && d.month == todayStart.month;
        return isLast30d || isThisMonth;
      case 'quarter':
        final quarterStart = DateTime(
          todayStart.year,
          ((todayStart.month - 1) ~/ 3) * 3 + 1,
          1,
        );
        final nextQuarterStart = DateTime(
          todayStart.year,
          ((todayStart.month - 1) ~/ 3) * 3 + 4,
          1,
        );
        return !d.isBefore(quarterStart) && d.isBefore(nextQuarterStart);
      case 'custom':
        if (_customFrom == null || _customTo == null) {
          final start30d = todayStart.subtract(const Duration(days: 29));
          final isLast30d = !d.isBefore(start30d) && d.isBefore(tomorrowStart);
          final isThisMonth =
              d.year == todayStart.year && d.month == todayStart.month;
          return isLast30d || isThisMonth;
        }
        final fromDate = _startOfDay(_customFrom!);
        final toDateTomorrow = _startOfDay(_customTo!)
            .add(const Duration(days: 1));
        return !d.isBefore(fromDate) && d.isBefore(toDateTomorrow);
      default:
        return true;
    }
  }

  bool _expenseMatchesPeriod(
    Expense expense,
    String period,
    DateTime todayStart,
  ) {
    final dueDt = _parseDate(expense.due);
    final dueMatches =
        dueDt != null && _matchesPeriod(dueDt, period, todayStart);
    if (expense.isPaid) {
      final paidDt = _parseDate(expense.paid);
      final paidMatches =
          paidDt != null && _matchesPeriod(paidDt, period, todayStart);
      return dueMatches || paidMatches;
    }
    return dueMatches;
  }

  Future<void> _showMarkPaidDatePicker(
    BuildContext context,
    Expense expense,
  ) async {
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

    if (picked != null && context.mounted) {
      final paidDateStr = DateFormatter.toIsoDateString(picked);
      context.read<OwnerBloc>().add(
        MarkExpensePaidEvent(expense.id, paidDate: paidDateStr),
      );
    }
  }

  void _openExpenseDetails(BuildContext context, Expense expense) {
    final bloc = context.read<OwnerBloc>();
    final outletScopeCubit = context.read<OutletScopeCubit?>();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MultiBlocProvider(
          providers: [
            BlocProvider<OwnerBloc>.value(value: bloc),
            if (outletScopeCubit != null)
              BlocProvider<OutletScopeCubit>.value(value: outletScopeCubit),
          ],
          child: ExpenseDetailScreen(expense: expense),
        ),
      ),
    );
  }

  void _showAddExpenseDialog(BuildContext context) {
    final bloc = context.read<OwnerBloc>();
    final outletScopeCubit = context.read<OutletScopeCubit?>();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MultiBlocProvider(
          providers: [
            BlocProvider<OwnerBloc>.value(value: bloc),
            if (outletScopeCubit != null)
              BlocProvider<OutletScopeCubit>.value(value: outletScopeCubit),
          ],
          child: const AddExpenseScreen(),
        ),
      ),
    );
  }

  /// Retry and pull-to-refresh both mean "sync": send what is queued first,
  /// then reload the list. A bare reload would not send anything, so a change
  /// saved offline would sit in the queue until the app was reopened.
  Future<void> _syncThenReload({Completer<void>? done}) async {
    final bloc = context.read<OwnerBloc>();
    await SyncEngine.instance.retryNow();
    if (!mounted) {
      done?.complete();
      return;
    }
    bloc.add(LoadExpensesEvent(refresh: true, done: done));
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final todayStart = _startOfDay(now);
    final outletScopeCubit = context.watch<OutletScopeCubit?>();
    final outletScope = outletScopeCubit?.state;

    final content = BlocConsumer<OwnerBloc, OwnerState>(
      listenWhen: (prev, curr) =>
          curr.messageSection == OwnerSection.expenses &&
          (curr.error != null || curr.actionMessage != null),
      listener: (context, state) {
        if (state.messageSection != OwnerSection.expenses) return;
        if (state.actionMessage != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.actionMessage!),
              backgroundColor: AppColors.success,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        if (state.error != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.error!),
              backgroundColor: AppColors.danger,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      },
      builder: (context, state) {
        final allExpenses = state.expenses;

        // 1. Compute stats within selected period
        int paidInPeriod = 0;
        int unpaidInPeriod = 0;
        for (final e in allExpenses) {
          if (e.isPaid) {
            final paidDt = _parseDate(e.paid);
            if (paidDt != null &&
                _matchesPeriod(paidDt, _selectedPeriod, todayStart)) {
              paidInPeriod += e.amount;
            }
          } else {
            final dueDt = _parseDate(e.due);
            if (dueDt != null &&
                _matchesPeriod(dueDt, _selectedPeriod, todayStart)) {
              unpaidInPeriod += e.amount;
            }
          }
        }

        // 2. Filter expenses by period
        final periodExpenses = allExpenses.where((e) {
          return _expenseMatchesPeriod(e, _selectedPeriod, todayStart);
        }).toList();

        final unpaidCountInPeriod = periodExpenses
            .where((e) => !e.isPaid)
            .length;

        // 3. Filter by search query and category/status chips
        final displayedExpenses = periodExpenses.where((e) {
          if (_searchQuery.isNotEmpty) {
            final q = _searchQuery.toLowerCase().trim();
            final matchesTitle = e.title.toLowerCase().contains(q);
            final matchesCategory = e.category.toLowerCase().contains(q);
            if (!matchesTitle && !matchesCategory) return false;
          }

          if (_activeFilter == 'unpaid') return !e.isPaid;
          if (_activeFilter == 'recurring') return e.monthly;
          return true;
        }).toList();

        final recurringShownCount = displayedExpenses
            .where((e) => e.monthly)
            .length;

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
            title: const OutletTitleSwitcher(
              screenLabel: 'Expenses',
              showAllOutletsOption: true,
            ),
            actions: [
              IconButton(
                icon: const Icon(
                  Icons.refresh_rounded,
                  color: AppColors.mutedText,
                  size: 20,
                ),
                tooltip: 'Refresh',
                onPressed: () {
                  context.read<OwnerBloc>().add(
                    LoadExpensesEvent(refresh: true),
                  );
                },
              ),
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
          body: Column(
            children: [
              SyncStatusBar(onSyncNow: _syncThenReload),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async {
                    final done = Completer<void>();
                    await _syncThenReload(done: done);
                    await done.future;
                  },
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(20),
                    children: [
                      // 1. Period selector row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Expense overview',
                            style: TextStyle(
                              fontFamily: AppTextStyles.fontDisplay,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppColors.text,
                            ),
                          ),
                          _PeriodSelector(
                            selectedPeriod: _selectedPeriod,
                            customFrom: _customFrom,
                            customTo: _customTo,
                            onPeriodChanged: (val) {
                              setState(() {
                                _selectedPeriod = val;
                                if (val != 'custom') {
                                  _customFrom = null;
                                  _customTo = null;
                                }
                              });
                            },
                          ),
                        ],
                      ),
                      if (_selectedPeriod == 'custom')
                        _buildCustomDateSelector(),
                      const SizedBox(height: 12),

                      // 2. Stats row
                      // Headline primary card: Paid in selected period
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(15),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Paid in selected period',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFFD9E7FF),
                              ),
                            ),
                            const SizedBox(height: 9),
                            Text(
                              CurrencyFormatter.format(paidInPeriod),
                              style: const TextStyle(
                                fontFamily: AppTextStyles.fontDisplay,
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Two secondary cards: Unpaid bills in period & Recurring bills shown
                      Row(
                        children: [
                          Expanded(
                            child: AppCard(
                              padding: const EdgeInsets.all(15),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Unpaid bills in period',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.mutedText,
                                    ),
                                  ),
                                  const SizedBox(height: 9),
                                  Text(
                                    CurrencyFormatter.format(unpaidInPeriod),
                                    style: TextStyle(
                                      fontFamily: AppTextStyles.fontDisplay,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800,
                                      color: unpaidInPeriod > 0
                                          ? AppColors.danger
                                          : AppColors.text,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: AppCard(
                              padding: const EdgeInsets.all(15),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Recurring bills shown',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.mutedText,
                                    ),
                                  ),
                                  const SizedBox(height: 9),
                                  Text(
                                    '$recurringShownCount',
                                    style: const TextStyle(
                                      fontFamily: AppTextStyles.fontDisplay,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.text,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // 3. Search box
                      Container(
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          border: Border.all(color: AppColors.controlBorder),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 13),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.search,
                              size: 19,
                              color: AppColors.mutedText,
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: TextField(
                                controller: _searchController,
                                style: const TextStyle(
                                  fontFamily: AppTextStyles.fontBody,
                                  fontSize: 14,
                                  color: AppColors.text,
                                ),
                                decoration: const InputDecoration(
                                  hintText: 'Search bills or categories...',
                                  hintStyle: TextStyle(
                                    fontFamily: AppTextStyles.fontBody,
                                    fontSize: 14,
                                    color: AppColors.faintText,
                                  ),
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                ),
                                onChanged: (val) {
                                  setState(() => _searchQuery = val);
                                },
                              ),
                            ),
                            if (_searchController.text.isNotEmpty)
                              InkWell(
                                onTap: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                                child: const Icon(
                                  Icons.close,
                                  size: 18,
                                  color: AppColors.mutedText,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // 4. Filter chips
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            AppFilterChip(
                              label: 'All',
                              isSelected: _activeFilter == 'all',
                              onTap: () =>
                                  setState(() => _activeFilter = 'all'),
                            ),
                            const SizedBox(width: 8),
                            AppFilterChip(
                              label: 'Unpaid $unpaidCountInPeriod',
                              isSelected: _activeFilter == 'unpaid',
                              onTap: () =>
                                  setState(() => _activeFilter = 'unpaid'),
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

                      // 5. Ledger list or Empty state
                      if (state.loading.contains(OwnerSection.expenses) &&
                          allExpenses.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 40),
                          child: Center(
                            child: CircularProgressIndicator(
                              color: AppColors.primary,
                            ),
                          ),
                        )
                      else if (displayedExpenses.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 30),
                          child: EmptyState(
                            icon: allExpenses.isEmpty
                                ? Icons.receipt_long_outlined
                                : Icons.search_off_outlined,
                            title: allExpenses.isEmpty
                                ? 'No expenses yet'
                                : 'No expenses match your filters',
                            subtitle: allExpenses.isEmpty
                                ? 'Add an expense using the + button above.'
                                : 'Try changing your period, search query, or filters.',
                            actionLabel: allExpenses.isEmpty
                                ? 'Add expense'
                                : 'Clear filters',
                            onAction: allExpenses.isEmpty
                                ? () => _showAddExpenseDialog(context)
                                : () {
                                    _searchController.clear();
                                    setState(() {
                                      _searchQuery = '';
                                      _activeFilter = 'all';
                                    });
                                  },
                          ),
                        )
                      else
                        ...displayedExpenses.map((expense) {
                          final dueDt = _parseDate(expense.due);
                          final isUpcoming =
                              !expense.isPaid &&
                              dueDt != null &&
                              dueDt.isAfter(todayStart);

                          final String attributionText;
                          if (expense.outletId == null ||
                              expense.outletId!.isEmpty) {
                            attributionText = 'Organization-wide';
                          } else {
                            final outlet = outletScope?.allowed
                                .where((o) => o.id == expense.outletId)
                                .firstOrNull;
                            attributionText =
                                outlet?.displayName ?? expense.outletId!;
                          }

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 11),
                            child: AppCard(
                              padding: const EdgeInsets.all(14),
                              onTap: () =>
                                  _openExpenseDetails(context, expense),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              expense.title,
                                              style: const TextStyle(
                                                fontFamily:
                                                    AppTextStyles.fontBody,
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
                                        const SizedBox(height: 2),
                                        Text(
                                          attributionText,
                                          style: const TextStyle(
                                            fontFamily: AppTextStyles.fontBody,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                            color: AppColors.mutedText,
                                          ),
                                        ),
                                        if (expense.isPaid &&
                                            expense.paid != null &&
                                            expense.paid!.isNotEmpty) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            'Paid ${expense.paid}',
                                            style: const TextStyle(
                                              fontFamily:
                                                  AppTextStyles.fontBody,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: AppColors.success,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        CurrencyFormatter.format(
                                          expense.amount,
                                        ),
                                        style: const TextStyle(
                                          fontFamily: AppTextStyles.fontDisplay,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                          color: AppColors.text,
                                        ),
                                      ),
                                      const SizedBox(height: 5),
                                      InkWell(
                                        onTap: !expense.isPaid
                                            ? () => _showMarkPaidDatePicker(
                                                context,
                                                expense,
                                              )
                                            : null,
                                        borderRadius: BorderRadius.circular(12),
                                        child: StatusPill(
                                          label: expense.isPaid
                                              ? 'Paid'
                                              : (isUpcoming
                                                    ? 'Upcoming'
                                                    : 'Unpaid'),
                                          variant: expense.isPaid
                                              ? PillVariant.paid
                                              : (isUpcoming
                                                    ? PillVariant.neutral
                                                    : PillVariant.warning),
                                        ),
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
              ),
            ],
          ),
        );
      },
    );

    if (outletScopeCubit == null) {
      return content;
    }

    return BlocListener<OutletScopeCubit, OutletScope>(
      bloc: outletScopeCubit,
      listenWhen: (prev, curr) =>
          prev.activeOutletId != curr.activeOutletId ||
          prev.allOutlets != curr.allOutlets,
      listener: (context, state) {
        context.read<OwnerBloc>().add(LoadExpensesEvent());
      },
      child: content,
    );
  }
}

class AddExpenseScreen extends StatefulWidget {
  const AddExpenseScreen({super.key});

  @override
  State<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends State<AddExpenseScreen> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  late final String _idempotencyKey = IdempotencyKeyGenerator.generate();
  String _category = 'Operations';
  late String _due = DateFormatter.todayIsoDateString();
  bool _monthly = false;
  bool _outletInitialized = false;
  String? _selectedOutletId;
  String? _errorMessage;

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _pickDueDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final current = DateFormatter.parseCalendarDate(_due) ?? today;

    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(today.year - 5, 1, 1),
      lastDate: DateTime(today.year + 5, 12, 31),
      helpText: 'Select due date',
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

    context.read<OwnerBloc>().add(
      AddExpenseEvent(
        title: title,
        category: _category,
        amount: amountInPaise,
        due: _due,
        monthly: _monthly,
        idempotencyKey: _idempotencyKey,
        outletId: _selectedOutletId,
        orgWide: _selectedOutletId == null,
      ),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final outletScope = context.watch<OutletScopeCubit?>()?.state;
    final allowedOutlets = outletScope?.allowed ?? const [];
    if (!_outletInitialized && outletScope != null) {
      _outletInitialized = true;
      if (!outletScope.allOutlets && outletScope.activeOutletId != null) {
        _selectedOutletId = outletScope.activeOutletId;
      } else {
        _selectedOutletId = null;
      }
    }

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
        title: const Text(
          'Add expense',
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
              items: [
                'Operations',
                'Supplies',
                'Rent',
                'Utilities',
                'Maintenance',
                'Other',
              ].map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
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
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.inset,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Recurring monthly expense',
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontBody,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Switch(
                    value: _monthly,
                    activeThumbColor: AppColors.primary,
                    onChanged: (v) => setState(() => _monthly = v),
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
            PrimaryButton(label: 'Save expense', onPressed: _handleSave),
          ],
        ),
      ),
    );
  }
}

class _PeriodSelector extends StatelessWidget {
  final String selectedPeriod;
  final DateTime? customFrom;
  final DateTime? customTo;
  final ValueChanged<String> onPeriodChanged;

  const _PeriodSelector({
    required this.selectedPeriod,
    this.customFrom,
    this.customTo,
    required this.onPeriodChanged,
  });

  static const _labels = {
    'today': 'Today',
    '7d': 'This week',
    '30d': 'This month',
    'quarter': 'This quarter',
    'custom': 'Custom dates',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.controlBorder),
        borderRadius: BorderRadius.circular(999),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selectedPeriod,
          icon: const Icon(
            Icons.expand_more,
            size: 16,
            color: AppColors.mutedText,
          ),
          style: const TextStyle(
            fontFamily: AppTextStyles.fontBody,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.text,
          ),
          onChanged: (val) {
            if (val != null) {
              onPeriodChanged(val);
            }
          },
          selectedItemBuilder: (context) {
            return _labels.entries.map((e) {
              String labelText = e.value;
              if (e.key == 'custom' && customFrom != null && customTo != null) {
                labelText =
                    '${DateFormatter.formatShort(customFrom!)} – ${DateFormatter.formatShort(customTo!)}';
              }
              return Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  labelText,
                  style: const TextStyle(
                    fontFamily: AppTextStyles.fontBody,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
              );
            }).toList();
          },
          items: _labels.entries.map((e) {
            return DropdownMenuItem<String>(value: e.key, child: Text(e.value));
          }).toList(),
        ),
      ),
    );
  }
}
