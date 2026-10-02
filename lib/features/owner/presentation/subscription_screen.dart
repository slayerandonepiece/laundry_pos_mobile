import 'package:myshop/shared/widgets/app_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:myshop/core/constants/app_colors.dart';
import 'package:myshop/core/theme/text_styles.dart';
import 'package:myshop/features/auth/bloc/auth_bloc.dart';
import 'package:myshop/features/auth/bloc/auth_state.dart';
import 'package:myshop/features/auth/data/models/user_model.dart';
import 'package:myshop/core/utils/currency_formatter.dart';
import 'package:myshop/core/utils/date_formatter.dart';
import 'package:myshop/features/owner/data/models/subscription_invoice_model.dart';
import 'package:myshop/features/owner/data/owner_repository.dart';
import 'package:myshop/features/owner/presentation/plan_status_helper.dart';
import 'package:myshop/features/owner/presentation/subscription_invoice_viewer_screen.dart';
import 'package:myshop/shared/widgets/app_card.dart';
import 'package:myshop/shared/widgets/section_header.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  List<SubscriptionInvoice> _invoices = const [];
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    final repo = context.read<OwnerRepository?>();
    _invoices = repo?.getCachedSubscriptionInvoices() ?? const [];
    _load();
  }

  /// The list on the phone shows at once; the server's answer replaces it.
  Future<void> _load() async {
    final repo = context.read<OwnerRepository?>();
    if (repo == null) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final fresh = await repo.listSubscriptionInvoices();
      if (!mounted) return;
      setState(() {
        _invoices = fresh;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthBloc>().state;
    StoreSummary? store;

    if (authState is AuthenticatedState) {
      store = authState.currentStore;
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
          'Subscription',
          style: TextStyle(
            fontFamily: AppTextStyles.fontDisplay,
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppColors.text,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: AppColors.border, height: 1),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeader(title: 'PLAN STATUS'),
              const SizedBox(height: 8),
              _buildPlanStatusCard(store),
              const SizedBox(height: 24),
              const SectionHeader(title: 'INVOICES'),
              const SizedBox(height: 8),
              _buildInvoices(context),
              const SizedBox(height: 20),
              _buildHelpRow(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlanStatusCard(StoreSummary? store) {
    final planStatus = resolvePlanStatus(store);

    if (planStatus.isUnavailable) {
      return AppCard(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Icon(Icons.info_outline, size: 22, color: AppColors.mutedText),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Plan status unavailable',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontBody,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    "Plan status isn't available right now.",
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.mutedText,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final Color titleColor;
    final Color subtitleColor;

    if (planStatus.isWarning) {
      titleColor = AppColors.warning;
      subtitleColor = AppColors.warning;
    } else if (planStatus.isSuccess) {
      titleColor = AppColors.success;
      subtitleColor = AppColors.success;
    } else {
      titleColor = AppColors.text;
      subtitleColor = AppColors.mutedText;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: planStatus.bgColor,
        border: Border.all(color: planStatus.borderColor),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(planStatus.icon, size: 24, color: planStatus.textColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  planStatus.title,
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontBody,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: titleColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  planStatus.subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    color: subtitleColor,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInvoices(BuildContext context) {
    if (_invoices.isEmpty) {
      if (_loading) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 28),
          child: Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          ),
        );
      }
      return AppCard(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _failed ? "Couldn't load your invoices" : 'No invoices yet',
              style: const TextStyle(
                fontFamily: AppTextStyles.fontBody,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _failed
                  ? 'Check your connection and try again.'
                  : 'Each subscription payment appears here as an invoice.',
              style: AppTextStyles.hint,
            ),
            if (_failed) ...[
              const SizedBox(height: 12),
              SecondaryButton(
                label: 'Try again',
                height: AppButtonHeight.inline,
                onPressed: _load,
              ),
            ],
          ],
        ),
      );
    }

    final totalPaid = _invoices.fold<int>(0, (sum, i) => sum + i.amount);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            _failed
                ? "Showing what's saved on this phone. Couldn't refresh."
                : '${_invoices.length} ${_invoices.length == 1 ? 'invoice' : 'invoices'} · ${CurrencyFormatter.format(totalPaid)} paid in total',
            style: AppTextStyles.hint,
          ),
        ),
        for (final invoice in _invoices) ...[
          _buildInvoiceTile(context, invoice),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _buildInvoiceTile(BuildContext context, SubscriptionInvoice invoice) {
    final covers = invoice.coversFrom != null && invoice.coversTo != null
        ? '${DateFormatter.formatFull(invoice.coversFrom)} – ${DateFormatter.formatFull(invoice.coversTo)}'
        : null;
    final paidLine = [
      'Paid ${DateFormatter.formatFull(invoice.paidAt)}',
      if (invoice.method != null && invoice.method!.isNotEmpty)
        invoice.method!.toUpperCase() == 'CASH' ? 'Cash' : invoice.method!,
    ].join(' · ');

    return AppCard(
      key: ValueKey('subscription-invoice-${invoice.invoiceSeq}'),
      padding: EdgeInsets.zero,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RepositoryProvider<OwnerRepository>.value(
            value: context.read<OwnerRepository>(),
            child: SubscriptionInvoiceViewerScreen(invoice: invoice),
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: AppColors.primaryTint,
                shape: BoxShape.circle,
              ),
              child: Icon(
                invoice.isDeposit
                    ? Icons.savings_outlined
                    : Icons.autorenew_rounded,
                size: 20,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    invoice.title,
                    style: const TextStyle(
                      fontFamily: AppTextStyles.fontBody,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(paidLine, style: AppTextStyles.hint),
                  if (covers != null) ...[
                    const SizedBox(height: 2),
                    Text('Covers $covers', style: AppTextStyles.hint),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  CurrencyFormatter.format(invoice.amount),
                  style: const TextStyle(
                    fontFamily: AppTextStyles.fontDisplay,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 3),
                Text(invoice.number, style: AppTextStyles.hint),
              ],
            ),
            const SizedBox(width: 4),
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Icon(
                Icons.chevron_right,
                size: 18,
                color: AppColors.faintText,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHelpRow(BuildContext context) {
    return SecondaryButton(
      label: 'Contact support about billing',
      icon: const Icon(Icons.help_outline, size: 16, color: AppColors.primary),
      height: AppButtonHeight.inline,
      textColor: AppColors.primary,
      onPressed: () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Contact support at support@klenpos.com'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
    );
  }
}
