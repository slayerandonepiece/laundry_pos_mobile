import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/storage/local_cache.dart';
import '../../../core/sync/server_action_queue.dart';
import '../../../core/sync/sync_engine.dart';
import '../../../core/theme/text_styles.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';

/// Requests that need the server's say-so (cancel an order, edit or delete a
/// bill), with where each one stands. They are sent in the background, so
/// nobody has to stay here: this is only for seeing what is waiting and for
/// retrying the ones the server refused.
class PendingRequestsScreen extends StatefulWidget {
  final LocalCacheService? cache;

  const PendingRequestsScreen({super.key, this.cache});

  @override
  State<PendingRequestsScreen> createState() => _PendingRequestsScreenState();
}

class _PendingRequestsScreenState extends State<PendingRequestsScreen> {
  late final LocalCacheService _cache = widget.cache ?? LocalCacheService();

  List<Map<String, dynamic>> _parked() {
    try {
      return _cache.getDeadLetterOwnerActionsQueue();
    } catch (_) {
      return const [];
    }
  }

  static const _names = {
    'update_store_profile': 'Store profile update',
    'set_staff_active': 'Staff on/off',
    'toggle_staff_active': 'Staff on/off',
    'create_expense': 'New bill',
    'mark_expense_paid': 'Mark bill paid',
    'toggle_payment_method': 'Payment method change',
    'upsert_product': 'Service save',
  };

  Future<void> _dismiss(Map<String, dynamic> a) async {
    final id = a['clientActionId'];
    await _cache.setDeadLetterOwnerActionsQueue([
      for (final x in _parked())
        if (x['clientActionId'] != id) x,
    ]);
    SyncEngine.instance.trigger();
    if (mounted) setState(() {});
  }

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
          'Pending requests',
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
      body: ValueListenableBuilder<List<ServerAction>>(
        valueListenable: ServerActionQueue.instance.actions,
        builder: (context, actions, _) {
          final parked = _parked();
          if (actions.isEmpty && parked.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Nothing is waiting for the server.',
                  key: Key('pending_requests_empty'),
                  textAlign: TextAlign.center,
                  style: AppTextStyles.hint,
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: actions.length + parked.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              if (i < actions.length) return _RequestCard(action: actions[i]);
              final a = parked[i - actions.length];
              return AppCard(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _names[a['type']] ?? a['type'].toString(),
                      style: const TextStyle(
                        fontFamily: AppTextStyles.fontBody,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Not saved: ${a['lastError'] ?? 'the server refused'}',
                      key: const Key('parked_owner_action'),
                      style: AppTextStyles.hint.copyWith(
                        color: AppColors.danger,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextActionButton(
                      label: 'Dismiss',
                      color: AppColors.danger,
                      onPressed: () => _dismiss(a),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  final ServerAction action;

  const _RequestCard({required this.action});

  @override
  Widget build(BuildContext context) {
    final failed = action.isFailed;
    final sending = ServerActionQueue.instance.isProcessing(action.id);
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            action.summary,
            style: const TextStyle(
              fontFamily: AppTextStyles.fontBody,
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            failed
                ? 'Not done: ${action.lastError ?? 'the server refused'}'
                : sending
                ? 'Sending to the server…'
                : 'Waiting for the server — sent automatically',
            key: Key('pending_request_status_${action.id}'),
            style: AppTextStyles.hint.copyWith(
              color: failed ? AppColors.danger : AppColors.mutedText,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (failed) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                ValueListenableBuilder<bool>(
                  valueListenable: SyncEngine.busy,
                  builder: (context, busy, _) => busy
                      ? const SizedBox(
                          key: Key('pending_request_retry_loader'),
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : TextActionButton(
                          label: 'Retry',
                          onPressed: () async {
                            await ServerActionQueue.instance.reviveFailed();
                            SyncEngine.instance.trigger();
                          },
                        ),
                ),
                const SizedBox(width: 12),
                TextActionButton(
                  label: 'Dismiss',
                  color: AppColors.danger,
                  onPressed: () =>
                      ServerActionQueue.instance.dismiss(action.id),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
