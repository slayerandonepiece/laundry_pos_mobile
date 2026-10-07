import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:myshop/core/constants/app_colors.dart';
import 'package:myshop/core/theme/text_styles.dart';
import 'package:myshop/features/orders/data/orders_repository.dart';
import 'package:myshop/shared/widgets/app_button.dart';
import 'package:myshop/shared/widgets/app_card.dart';

/// More > Customer messages. The text Share update drafts at each order
/// status, as set for the organization. Read-only: the phone keeps the copy
/// the server last sent and refreshes it when opened.
class CustomerMessagesScreen extends StatefulWidget {
  const CustomerMessagesScreen({super.key});

  @override
  State<CustomerMessagesScreen> createState() => _CustomerMessagesScreenState();
}

class _CustomerMessagesScreenState extends State<CustomerMessagesScreen> {
  List<Map<String, dynamic>> _templates = const [];
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _templates =
        context.read<OrdersRepository>().getCachedMessageTemplates() ??
        const [];
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final fresh = await context
          .read<OrdersRepository>()
          .syncMessageTemplates();
      if (!mounted) return;
      setState(() {
        _templates = fresh;
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

  static String _attachment(String? key) => switch (key) {
    'ORDER_SLIP_PDF' => 'Order slip PDF attached',
    'INVOICE_PDF' => 'Invoice PDF attached',
    _ => 'No attachment',
  };

  @override
  Widget build(BuildContext context) {
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
          'Customer messages',
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
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Share update drafts one of these messages for each order '
              'status. Contact support to change them.',
              style: AppTextStyles.hint,
            ),
            const SizedBox(height: 16),
            if (_templates.isEmpty)
              _empty()
            else ...[
              if (_failed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    "Showing what's saved on this phone. Couldn't refresh.",
                    style: AppTextStyles.hint.copyWith(
                      color: AppColors.warning,
                    ),
                  ),
                ),
              for (final t in _templates) ...[
                _card(t),
                const SizedBox(height: 10),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _empty() {
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
          const Text("Couldn't load your messages", style: _titleStyle),
          const SizedBox(height: 4),
          Text(
            'Check your connection and try again.',
            style: AppTextStyles.hint,
          ),
          const SizedBox(height: 12),
          SecondaryButton(
            label: 'Try again',
            height: AppButtonHeight.inline,
            onPressed: _load,
          ),
        ],
      ),
    );
  }

  Widget _card(Map<String, dynamic> t) {
    final on = t['enabled'] == true;
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  t['label']?.toString() ?? t['statusKey'].toString(),
                  style: _titleStyle,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: on ? AppColors.successBg : AppColors.neutralBg,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  on ? 'On' : 'Off',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: on ? AppColors.success : AppColors.mutedText,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            _attachment(t['attachment']?.toString()),
            style: AppTextStyles.hint,
          ),
          const SizedBox(height: 10),
          Text(
            t['body']?.toString() ?? '',
            style: TextStyle(
              fontSize: 13.5,
              height: 1.4,
              color: on ? AppColors.text : AppColors.mutedText,
            ),
          ),
        ],
      ),
    );
  }

  static const _titleStyle = TextStyle(
    fontFamily: AppTextStyles.fontBody,
    fontSize: 15,
    fontWeight: FontWeight.w700,
    color: AppColors.text,
  );
}
