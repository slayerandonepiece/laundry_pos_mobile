import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:myshop/core/constants/app_colors.dart';
import 'package:myshop/core/theme/text_styles.dart';
import 'package:myshop/core/utils/currency_formatter.dart';
import 'package:myshop/core/utils/date_formatter.dart';
import 'package:myshop/features/auth/bloc/auth_bloc.dart';
import 'package:myshop/features/auth/bloc/auth_state.dart';
import 'package:myshop/features/orders/bloc/orders_bloc.dart';
import 'package:myshop/features/orders/bloc/orders_event.dart';
import 'package:myshop/features/orders/bloc/orders_state.dart';
import 'package:myshop/features/orders/data/models/order_model.dart';
import 'package:myshop/features/orders/presentation/dialogs/collect_payment_dialog.dart';
import 'package:myshop/features/orders/presentation/dialogs/ready_bill_actions_sheet.dart';
import 'package:myshop/features/orders/presentation/dialogs/record_payment_dialog.dart';
import 'package:myshop/features/orders/presentation/dialogs/status_dialog.dart';
import 'package:myshop/features/orders/presentation/invoice_actions_sheet.dart';
import 'package:myshop/features/orders/presentation/invoice_viewer_screen.dart';
import 'package:myshop/features/orders/presentation/order_activity_screen.dart';
import 'package:myshop/shared/widgets/app_button.dart';
import 'package:myshop/shared/widgets/app_card.dart';
import 'package:myshop/shared/widgets/app_inset.dart';
import 'package:myshop/shared/widgets/status_pill.dart';
import 'package:url_launcher/url_launcher.dart';

class OrderDetailScreen extends StatefulWidget {
  final Order initialOrder;

  const OrderDetailScreen({super.key, required this.initialOrder});

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  late Order _order;

  @override
  void initState() {
    super.initState();
    // Show the cached order (passed in from the list, already loaded from
    // local cache with no network call) immediately. A network fetch only
    // ever happens when the user explicitly pulls to refresh below — never
    // on open, so opening an order detail is always instant regardless of
    // connectivity.
    _order = widget.initialOrder;
  }

  Future<void> _promptNotifyCustomerReady(
    BuildContext context,
    Order order,
    String storeName,
  ) async {
    final shouldNotify = await showDialog<bool>(
      context: context,
      barrierColor: AppColors.scrim.withValues(alpha: 0.42),
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Notify customer now?', style: AppTextStyles.h2),
              const SizedBox(height: 8),
              const Text(
                'Order is ready for pickup. Send the customer their bill now?',
                style: AppTextStyles.hint,
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        side: const BorderSide(color: AppColors.controlBorder),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(9),
                        ),
                      ),
                      child: const Text(
                        'Skip',
                        style: AppTextStyles.buttonSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        backgroundColor: AppColors.primary,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(9),
                        ),
                      ),
                      child: const Text(
                        'Yes, notify',
                        style: AppTextStyles.button,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (shouldNotify == true && context.mounted) {
      await ReadyBillActionsSheet.show(
        context,
        order: order,
        storeName: storeName,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthBloc>().state;
    final String storeName = authState is AuthenticatedState
        ? authState.currentStore.storeName
        : '';

    return BlocConsumer<OrdersBloc, OrdersState>(
      listener: (context, state) {
        if (state.selectedOrder != null &&
            state.selectedOrder!.isSameOrder(widget.initialOrder)) {
          setState(() {
            _order = state.selectedOrder!;
          });
        }
        if (state.actionSuccessMessage != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.actionSuccessMessage!),
              backgroundColor: AppColors.success,
              behavior: SnackBarBehavior.floating,
            ),
          );
          if (state.actionSuccessMessage == 'Status updated to Ready' &&
              state.selectedOrder != null &&
              state.selectedOrder!.isSameOrder(widget.initialOrder)) {
            // StatusDialog listens on this same bloc and pops itself on this
            // same state change. Its listener runs after this one, so
            // pushing the notify dialog synchronously here would land it on
            // top of StatusDialog before StatusDialog's own pop runs —
            // making that pop close the notify dialog instead of
            // StatusDialog. Deferring to the next frame guarantees
            // StatusDialog has already closed first.
            final order = state.selectedOrder!;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (context.mounted) {
                _promptNotifyCustomerReady(context, order, storeName);
              }
            });
          }
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
        // state.selectedOrder is shared bloc-wide state, set by whichever
        // order any screen last acted on (status update, payment, refresh —
        // see orders_bloc.dart). It's only this screen's order if the codes
        // match; otherwise it's a stale value left over from a different
        // order and must not override this screen's own _order.
        final order =
            (state.selectedOrder?.isSameOrder(widget.initialOrder) == true
                ? state.selectedOrder
                : null) ??
            _order;
        final isDelivered = order.isDelivered;
        final hasBalanceDue = order.balanceDue > 0;
        final isReady = order.status.toLowerCase() == 'ready';

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
                Text(
                  order.displayCode,
                  style: const TextStyle(
                    fontFamily: AppTextStyles.fontDisplay,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Placed ${DateFormatter.formatDate(order.createdAt)} · ready by ${DateFormatter.formatDate(order.due)}',
                  style: AppTextStyles.hint,
                ),
              ],
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(child: StatusPill.fromStatus(order.status)),
              ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Container(color: AppColors.border, height: 1),
            ),
          ),
          body: RefreshIndicator(
            onRefresh: () async {
              final bloc = context.read<OrdersBloc>();
              bloc.add(LoadOrderDetailEvent(order.orderCode));
              await bloc.stream.firstWhere((s) => !s.isLoading);
            },
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // 1. Horizontal Step Timeline
                _buildTimeline(order.status),
                const SizedBox(height: 14),

                // 2. Customer Info Card
                AppCard(
                  padding: const EdgeInsets.all(15),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            order.name.isNotEmpty
                                ? order.name
                                : 'Walk-in Customer',
                            style: const TextStyle(
                              fontFamily: AppTextStyles.fontBody,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.text,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '+91 ${order.phone}',
                            style: const TextStyle(
                              fontFamily: AppTextStyles.fontBody,
                              fontSize: 12.5,
                              color: AppColors.mutedText,
                            ),
                          ),
                        ],
                      ),
                      InkWell(
                        onTap: () async {
                          final cleanPhone = order.phone.replaceAll(
                            RegExp(r'[^0-9]'),
                            '',
                          );
                          final url = Uri.parse('tel:$cleanPhone');
                          if (await canLaunchUrl(url)) {
                            await launchUrl(url);
                          }
                        },
                        borderRadius: BorderRadius.circular(99),
                        child: Container(
                          width: 42,
                          height: 42,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.primaryTint,
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.phone_outlined,
                              size: 20,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // 3. Order Items & Balance Card
                AppCard(
                  padding: const EdgeInsets.all(15),
                  child: Column(
                    children: [
                      ...order.lines.map(
                        (line) => Padding(
                          padding: const EdgeInsets.only(bottom: 11),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: RichText(
                                  text: TextSpan(
                                    style: const TextStyle(
                                      fontFamily: AppTextStyles.fontBody,
                                      fontSize: 13.5,
                                      color: AppColors.text,
                                    ),
                                    children: [
                                      TextSpan(text: line.productName),
                                      TextSpan(
                                        text: ' · ${line.displayQuantity}',
                                        style: const TextStyle(
                                          color: AppColors.mutedText,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              Text(
                                CurrencyFormatter.format(line.totalAmount),
                                style: const TextStyle(
                                  fontFamily: AppTextStyles.fontDisplay,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.text,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Divider(color: AppColors.border, height: 16),

                      // Payment summary
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            order.payments.isNotEmpty
                                ? 'Collected · ${order.payments.first.method}'
                                : 'Pay on delivery',
                            style: const TextStyle(
                              fontFamily: AppTextStyles.fontBody,
                              fontSize: 12.5,
                              color: AppColors.mutedText,
                            ),
                          ),
                          Text(
                            order.payments.isNotEmpty
                                ? CurrencyFormatter.format(order.paidAmount)
                                : 'nothing collected yet',
                            style: const TextStyle(
                              fontFamily: AppTextStyles.fontBody,
                              fontSize: 12.5,
                              color: AppColors.mutedText,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Balance line
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          if (hasBalanceDue) ...[
                            const Text(
                              'Balance due',
                              style: TextStyle(
                                fontFamily: AppTextStyles.fontBody,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppColors.danger,
                              ),
                            ),
                            Text(
                              CurrencyFormatter.format(order.balanceDue),
                              style: const TextStyle(
                                fontFamily: AppTextStyles.fontDisplay,
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: AppColors.danger,
                              ),
                            ),
                          ] else ...[
                            const Row(
                              children: [
                                Icon(
                                  Icons.check_circle,
                                  size: 17,
                                  color: AppColors.success,
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'Paid in full',
                                  style: TextStyle(
                                    fontFamily: AppTextStyles.fontBody,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.success,
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              CurrencyFormatter.format(order.totalAmount),
                              style: const TextStyle(
                                fontFamily: AppTextStyles.fontDisplay,
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: AppColors.text,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // 4. Care instructions (if present)
                if (order.notes.isNotEmpty) ...[
                  AppCard(
                    padding: const EdgeInsets.all(15),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.notes_outlined,
                          size: 19,
                          color: AppColors.mutedText,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'CARE INSTRUCTIONS',
                                style: TextStyle(
                                  fontFamily: AppTextStyles.fontBody,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.mutedText,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                order.notes,
                                style: const TextStyle(
                                  fontFamily: AppTextStyles.fontBody,
                                  fontSize: 13,
                                  color: AppColors.text,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // 5. Actions / Invoice Section
                if (!isDelivered) ...[
                  // Pre-settlement flow. "Collect payment & deliver" is one
                  // constant action once the order is ready — the dialog
                  // itself branches on whether a balance is due, instead of
                  // this screen choosing between two different dialogs.
                  if (isReady) ...[
                    PrimaryButton(
                      label: 'Collect payment & deliver',
                      icon: const Icon(
                        Icons.payments_outlined,
                        size: 19,
                        color: Colors.white,
                      ),
                      onPressed: () {
                        CollectPaymentDialog.show(context, order: order);
                      },
                    ),
                    if (order.balanceDue > 0) ...[
                      const SizedBox(height: 10),
                      SecondaryButton(
                        label: 'Record payment',
                        onPressed: () {
                          RecordPaymentDialog.show(context, order: order);
                        },
                      ),
                    ],
                    const SizedBox(height: 10),
                    SecondaryButton(
                      label: 'Update status',
                      onPressed: () {
                        StatusDialog.show(
                          context,
                          order: order,
                          onCollectPaymentRequested: () {
                            CollectPaymentDialog.show(context, order: order);
                          },
                        );
                      },
                    ),
                  ] else ...[
                    PrimaryButton(
                      label: 'Update status',
                      onPressed: () {
                        StatusDialog.show(context, order: order);
                      },
                    ),
                    if (order.balanceDue > 0) ...[
                      const SizedBox(height: 10),
                      SecondaryButton(
                        label: 'Record payment',
                        onPressed: () {
                          RecordPaymentDialog.show(context, order: order);
                        },
                      ),
                    ],
                  ],
                  const SizedBox(height: 12),

                  // Inset message
                  AppInset(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.lock_outline,
                          size: 18,
                          color: AppColors.faintText,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'The invoice is created once this order is paid in full and marked delivered.',
                            style: AppTextStyles.hint.copyWith(
                              color: AppColors.faintText,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  // Settled / Delivered Flow (Screen 9f)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 15,
                      vertical: 13,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.selectedSurface,
                      border: Border.all(color: const Color(0xFFCDDFFC)),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'INVOICE',
                              style: TextStyle(
                                fontFamily: AppTextStyles.fontBody,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.mutedText,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              order.invoice?.invoiceNumber ??
                                  'INV-${order.displayCode}',
                              style: const TextStyle(
                                fontFamily: AppTextStyles.fontDisplay,
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          DateFormatter.formatDate(
                            order.invoice?.issuedAt ?? DateTime.now(),
                          ),
                          style: AppTextStyles.hint,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  // 3 Action Buttons: View, WhatsApp, More
                  Row(
                    children: [
                      Expanded(
                        child: _buildIconButton(
                          icon: Icons.visibility_outlined,
                          label: 'View',
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => InvoiceViewerScreen(
                                  order: order,
                                  storeName: storeName,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: _buildIconButton(
                          icon: Icons.chat_bubble_outline,
                          iconColor: AppColors.success,
                          label: 'WhatsApp',
                          onTap: () async {
                            final invoiceNo =
                                order.invoice?.invoiceNumber ??
                                'INV-${order.displayCode}';
                            final text = Uri.encodeComponent(
                              'Hello ${order.name.isNotEmpty ? order.name : "Customer"},\n'
                              'Your laundry order ${order.displayCode} ($invoiceNo) has been completed and delivered.\n'
                              'Total: ${CurrencyFormatter.format(order.totalAmount)} (Paid in full).\n'
                              '${storeName.isNotEmpty ? "Thank you for choosing $storeName!" : "Thank you for your business!"}',
                            );
                            final cleanPhone = order.phone.replaceAll(
                              RegExp(r'[^0-9]'),
                              '',
                            );
                            final url = Uri.parse(
                              'https://wa.me/91$cleanPhone?text=$text',
                            );
                            if (await canLaunchUrl(url)) {
                              await launchUrl(
                                url,
                                mode: LaunchMode.externalApplication,
                              );
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: _buildIconButton(
                          icon: Icons.more_horiz,
                          label: 'More',
                          onTap: () {
                            InvoiceActionsSheet.show(
                              context,
                              order: order,
                              storeName: storeName,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 14),

                // 6. Activity & History Button Card
                AppCard(
                  padding: EdgeInsets.zero,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => OrderActivityScreen(order: order),
                      ),
                    );
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 15, vertical: 14),
                    child: Row(
                      children: [
                        Icon(
                          Icons.history_outlined,
                          size: 20,
                          color: AppColors.primary,
                        ),
                        SizedBox(width: 13),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Activity & history',
                                style: TextStyle(
                                  fontFamily: AppTextStyles.fontBody,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.text,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Delivery commitment, who changed what',
                                style: TextStyle(
                                  fontFamily: AppTextStyles.fontBody,
                                  fontSize: 11,
                                  color: AppColors.mutedText,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right,
                          size: 18,
                          color: AppColors.faintText,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTimeline(String currentStatus) {
    final stages = ['Pending', 'In Progress', 'Ready', 'Delivered'];
    final normalized = currentStatus.toLowerCase();

    int currentIndex = 0;
    if (normalized == 'in progress') currentIndex = 1;
    if (normalized == 'ready') currentIndex = 2;
    if (normalized == 'delivered') currentIndex = 3;

    return Row(
      children: List.generate(stages.length * 2 - 1, (index) {
        if (index.isOdd) {
          // Connecting line
          final stageBeforeIndex = index ~/ 2;
          final isCompleted = stageBeforeIndex < currentIndex;
          return Expanded(
            child: Container(
              height: 2,
              color: isCompleted ? AppColors.success : AppColors.border,
              margin: const EdgeInsets.only(bottom: 22),
            ),
          );
        }

        final stageIndex = index ~/ 2;
        // The terminal stage (Delivered) is never superseded by a later one,
        // so reaching it as the current stage IS completion — show it
        // checked like every other stage does once passed, not as "current".
        final isLastStage = stageIndex == stages.length - 1;
        final isCompleted =
            stageIndex < currentIndex ||
            (isLastStage && stageIndex == currentIndex);
        final isCurrent = stageIndex == currentIndex && !isCompleted;

        return Expanded(
          child: Column(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isCompleted
                      ? AppColors.success
                      : (isCurrent ? AppColors.surface : AppColors.surface),
                  border: isCompleted
                      ? null
                      : Border.all(
                          color: isCurrent
                              ? AppColors.primary
                              : AppColors.controlBorder,
                          width: isCurrent ? 2.5 : 1.5,
                        ),
                ),
                child: isCompleted
                    ? const Center(
                        child: Icon(Icons.check, size: 13, color: Colors.white),
                      )
                    : null,
              ),
              const SizedBox(height: 7),
              Text(
                stages[stageIndex],
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: AppTextStyles.fontBody,
                  fontSize: 10.5,
                  fontWeight: (isCompleted || isCurrent)
                      ? FontWeight.w700
                      : FontWeight.w500,
                  color: isCompleted
                      ? AppColors.success
                      : (isCurrent ? AppColors.primary : AppColors.faintText),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    Color? iconColor,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.controlBorder),
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 19, color: iconColor ?? AppColors.text),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                fontFamily: AppTextStyles.fontBody,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
