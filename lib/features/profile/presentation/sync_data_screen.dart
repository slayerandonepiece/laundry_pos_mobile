import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:myshop/core/constants/app_colors.dart';
import 'package:myshop/core/storage/local_cache.dart';
import 'package:myshop/core/sync/sync_engine.dart';
import 'package:myshop/core/theme/text_styles.dart';
import 'package:myshop/features/auth/bloc/auth_bloc.dart';
import 'package:myshop/features/auth/bloc/auth_state.dart';
import 'package:myshop/features/auth/data/auth_repository.dart';
import 'package:myshop/features/orders/data/orders_repository.dart';
import 'package:myshop/features/owner/data/owner_repository.dart';
import 'package:myshop/features/pos/data/pos_repository.dart';
import 'package:myshop/shared/widgets/app_button.dart';
import 'package:myshop/shared/widgets/app_card.dart';

/// One thing the phone keeps a copy of, and how to refresh it.
class _Dataset {
  final String name;
  final bool ownerOnly;

  /// Refreshes the data and returns a short result, e.g. "12 services".
  final Future<String> Function() run;

  const _Dataset(this.name, this.run, {this.ownerOnly = false});
}

/// Settings > Sync data. One place to refresh the data that matters, so
/// "my screen looks wrong" has a first answer: open here and sync.
class SyncDataScreen extends StatefulWidget {
  const SyncDataScreen({super.key});

  @override
  State<SyncDataScreen> createState() => _SyncDataScreenState();
}

class _SyncDataScreenState extends State<SyncDataScreen> {
  final _cache = LocalCacheService();
  final _busy = <String>{};
  final _result = <String, String>{};
  final _failed = <String>{};
  bool _sending = false;

  /// Datasets the server has changed since this phone last synced them,
  /// found by the Status check.
  final _serverNewer = <String>{};

  /// Orders are kept per outlet, so their last-synced time is too.
  String _syncKey(String dataset) => dataset == 'Orders'
      ? 'Orders::${_cache.getActiveOutletId() ?? (_cache.isAllOutletsScope() ? 'all' : 'none')}'
      : dataset;

  @override
  void initState() {
    super.initState();
    // Coming back to the page: find out what the server has changed since the
    // last sync, so the rows are right without tapping Status. Offline, the
    // stored times still show.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        await _checkServer(context.read<OrdersRepository>());
        await _cache.setSyncedAt('Status');
        if (mounted) setState(() {});
      } catch (_) {}
    });
  }

  Future<String> _checkServer(OrdersRepository orders) async {
    final server = await orders.getServerChangeTimes();
    _serverNewer.clear();
    const keys = {
      'Services and prices': 'productsUpdatedAt',
      'Orders': 'ordersUpdatedAt',
      'Profile': 'profileUpdatedAt',
      'Payment methods': 'paymentMethodsUpdatedAt',
      'Message templates': 'messageTemplatesUpdatedAt',
      'Expenses': 'expensesUpdatedAt',
      'Employees': 'employeesUpdatedAt',
      'Invoices': 'invoicesUpdatedAt',
    };
    // Compared with the last sync time. A server value that moves back after
    // a delete is not caught.
    keys.forEach((dataset, key) {
      final serverAt = server[key];
      final mine = _cache.getSyncedAt(_syncKey(dataset));
      if (serverAt != null && (mine == null || serverAt.isAfter(mine))) {
        _serverNewer.add(dataset);
      }
    });
    return _serverNewer.isEmpty
        ? 'Signed in. Nothing newer on the server.'
        : 'Signed in. The server has newer data.';
  }

  List<_Dataset> _datasets() {
    final pos = context.read<PosRepository>();
    final orders = context.read<OrdersRepository>();
    final owner = context.read<OwnerRepository>();
    final auth = context.read<AuthRepository>();
    return [
      _Dataset('Status', () async {
        final session = await auth.checkSession();
        if (session == null) throw Exception('not signed in');
        return _checkServer(orders);
      }),
      _Dataset('Profile', () async {
        final profile = await owner.getStoreProfile();
        return profile.storeName.isEmpty
            ? 'Profile updated'
            : profile.storeName;
      }),
      _Dataset('Services and prices', () async {
        final list = await pos.listProducts();
        return '${list.length} services';
      }),
      _Dataset('Payment methods', () async {
        final list = await pos.listPaymentMethods();
        return '${list.length} methods';
      }),
      _Dataset('Orders', () async {
        final ok = await orders.syncOrdersDelta();
        if (!ok) throw Exception('not reached');
        return 'Orders up to date';
      }),
      _Dataset('Message templates', () async {
        final rows = await orders.syncMessageTemplates();
        return '${rows.length} templates';
      }),
      _Dataset('Expenses', () async {
        final list = await owner.listExpenses();
        return '${list.length} expenses';
      }, ownerOnly: true),
      _Dataset('Employees', () async {
        final list = await owner.listStaff();
        return '${list.length} employees';
      }, ownerOnly: true),
      _Dataset('Invoices', () async {
        final list = await owner.listSubscriptionInvoices();
        return '${list.length} invoices';
      }, ownerOnly: true),
    ];
  }

  Future<void> _run(_Dataset d) async {
    if (_busy.contains(d.name)) return;
    setState(() {
      _busy.add(d.name);
      _failed.remove(d.name);
    });
    try {
      _result[d.name] = await d.run();
      await _cache.setSyncedAt(_syncKey(d.name));
      _serverNewer.remove(d.name);
    } catch (_) {
      _failed.add(d.name);
      _result[d.name] = "Couldn't update. Check your connection.";
    }
    if (mounted) setState(() => _busy.remove(d.name));
  }

  Future<void> _syncEverything(List<_Dataset> datasets) async {
    // Unsent changes go first, so a refresh never lands on top of them.
    await SyncEngine.instance.retryNow();
    for (final d in datasets) {
      await _run(d);
    }
    // Status ran first, so its "server has newer data" is out of date now.
    if (_failed.isEmpty && mounted) {
      setState(
        () => _result['Status'] = 'Signed in. Everything is up to date.',
      );
    }
  }

  Future<void> _sendNow() async {
    setState(() => _sending = true);
    try {
      await SyncEngine.instance.retryNow();
    } catch (_) {}
    if (mounted) setState(() => _sending = false);
  }

  /// The oldest sync among the rows shown: the page is only as fresh as that.
  String _lastSynced(List<_Dataset> datasets) {
    DateTime? oldest;
    for (final d in datasets) {
      final at = _cache.getSyncedAt(_syncKey(d.name));
      if (at == null) return 'Some data has not been synced yet.';
      if (oldest == null || at.isBefore(oldest)) oldest = at;
    }
    return oldest == null ? '' : 'Last synced ${_ago(oldest)}.';
  }

  String _ago(DateTime at) {
    final diff = DateTime.now().difference(at);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} h ago';
    return '${diff.inDays} d ago';
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthBloc>().state;
    final isOwner = auth is AuthenticatedState && auth.currentStore.isOwner;
    final datasets = [
      for (final d in _datasets())
        if (isOwner || !d.ownerOnly) d,
    ];
    var pending = 0;
    var parked = 0;
    try {
      pending = _cache.getTotalPendingCount();
      parked = _cache.getTotalDeadLetterCount();
    } catch (_) {}
    final anyBusy = _busy.isNotEmpty;

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
          'Sync data',
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
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'If something looks out of date, sync it here. Changes saved on '
            'this phone are sent first, so nothing is lost.',
            style: AppTextStyles.hint,
          ),
          const SizedBox(height: 16),
          Text(_lastSynced(datasets), style: AppTextStyles.hint),
          const SizedBox(height: 10),
          PrimaryButton(
            label: _serverNewer.isEmpty
                ? 'Sync everything'
                : 'Sync now (${_serverNewer.length} updated on server)',
            isLoading: anyBusy,
            onPressed: anyBusy ? null : () => _syncEverything(datasets),
          ),
          const SizedBox(height: 16),
          _pendingCard(pending, parked),
          const SizedBox(height: 10),
          for (final d in datasets) ...[_row(d), const SizedBox(height: 10)],
        ],
      ),
    );
  }

  /// One small round icon that carries the state, so a list of rows can be
  /// scanned: done, needs a sync, working, or failed.
  Widget _stateIcon(IconData icon, Color color, Color bg, {bool busy = false}) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Center(
        child: busy
            ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: color),
              )
            : Icon(icon, size: 19, color: color),
      ),
    );
  }

  /// Unsent changes. The button only appears when something is waiting.
  Widget _pendingCard(int pending, int parked) {
    final waiting = pending > 0;
    final stuck = parked > 0;
    final (IconData icon, Color color, Color bg) = stuck
        ? (Icons.error_outline, AppColors.danger, AppColors.dangerBg)
        : waiting
        ? (Icons.schedule, AppColors.warning, AppColors.warningBg)
        : (Icons.check, AppColors.success, AppColors.successBg);
    final title = stuck
        ? 'Some changes need attention'
        : waiting
        ? '$pending ${pending == 1 ? 'change' : 'changes'} waiting to send'
        : 'All changes sent';
    final detail = stuck
        ? "$parked couldn't be sent. Contact support."
        : waiting
        ? 'Saved on this phone. They send when you are online.'
        : 'Nothing is waiting on this phone.';
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          _stateIcon(icon, color, bg, busy: _sending),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: _titleStyle),
                const SizedBox(height: 3),
                Text(
                  detail,
                  style: AppTextStyles.hint.copyWith(
                    color: stuck ? AppColors.danger : AppColors.mutedText,
                  ),
                ),
              ],
            ),
          ),
          if (waiting) ...[
            const SizedBox(width: 10),
            SizedBox(
              width: 104,
              child: SecondaryButton(
                label: _sending ? 'Sending…' : 'Send now',
                height: AppButtonHeight.inline,
                onPressed: _sending ? null : _sendNow,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(_Dataset d) {
    final at = _cache.getSyncedAt(_syncKey(d.name));
    final busy = _busy.contains(d.name);
    final failed = _failed.contains(d.name);
    final stale = _serverNewer.contains(d.name);
    final never = at == null && _result[d.name] == null;

    final (IconData icon, Color color, Color bg) = failed
        ? (Icons.error_outline, AppColors.danger, AppColors.dangerBg)
        : stale
        ? (Icons.arrow_downward_rounded, AppColors.warning, AppColors.warningBg)
        : never
        ? (Icons.sync, AppColors.mutedText, AppColors.neutralBg)
        : (Icons.check, AppColors.success, AppColors.successBg);

    final detail = busy
        ? 'Syncing…'
        : failed
        ? "Couldn't update. Check your connection."
        : stale
        ? 'Newer data on the server'
        : never
        ? 'Not synced yet'
        : [?_result[d.name], 'Updated ${_ago(at!)}'].join(' · ');

    // Needs a sync -> clear outlined button. Already fresh -> quiet text.
    final needs = failed || stale || never;
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          _stateIcon(icon, color, bg, busy: busy),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(d.name, style: _titleStyle),
                const SizedBox(height: 3),
                Text(
                  detail,
                  style: AppTextStyles.hint.copyWith(
                    color: failed
                        ? AppColors.danger
                        : stale
                        ? AppColors.warning
                        : AppColors.mutedText,
                    fontWeight: stale ? FontWeight.w600 : null,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 104,
            child: needs || busy
                ? SecondaryButton(
                    label: busy ? 'Syncing…' : (failed ? 'Retry' : 'Sync'),
                    height: AppButtonHeight.inline,
                    onPressed: busy ? null : () => _run(d),
                  )
                : TextActionButton(label: 'Refresh', onPressed: () => _run(d)),
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
