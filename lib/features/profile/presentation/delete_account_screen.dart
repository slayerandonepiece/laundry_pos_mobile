import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:myshop/core/constants/app_colors.dart';
import 'package:myshop/core/network/api_exceptions.dart';
import 'package:myshop/core/storage/local_cache.dart';
import 'package:myshop/core/sync/connectivity_service.dart';
import 'package:myshop/core/theme/text_styles.dart';
import 'package:myshop/core/utils/date_formatter.dart';
import 'package:myshop/features/auth/bloc/auth_bloc.dart';
import 'package:myshop/features/auth/bloc/auth_event.dart';
import 'package:myshop/features/auth/bloc/auth_state.dart';
import 'package:myshop/features/auth/data/auth_repository.dart';
import 'package:myshop/shared/widgets/app_button.dart';
import 'package:myshop/shared/widgets/app_inset.dart';
import 'package:myshop/shared/widgets/app_text_field.dart';

/// Days between the request and the permanent wipe. The server owns the real
/// date (it returns `scheduledFor`); this only words the warning before the
/// request is sent.
const int accountDeletionGraceDays = 90;

/// Reached from Profile. An owner deletes the whole store, an employee deletes
/// only their own login. Either way the data is wiped after the grace period
/// and signing in again before then restores it.
class DeleteAccountScreen extends StatefulWidget {
  final ConnectivityService? connectivityService;
  final LocalCacheService? localCache;
  final AuthRepository? authRepository;

  const DeleteAccountScreen({
    super.key,
    this.connectivityService,
    this.localCache,
    this.authRepository,
  });

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  final TextEditingController _confirmController = TextEditingController();
  bool _submitting = false;
  String? _error;
  String? _scheduledFor;

  @override
  void initState() {
    super.initState();
    _confirmController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit(AuthenticatedState auth) async {
    final connectivity =
        widget.connectivityService ?? ConnectivityService.instance;
    final cache = widget.localCache ?? LocalCacheService();
    final repo = widget.authRepository ?? context.read<AuthRepository>();

    setState(() {
      _submitting = true;
      _error = null;
    });

    if (await connectivity.checkIsOffline()) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = "You're offline. Connect to the internet to delete.";
      });
      return;
    }
    if (cache.getPendingSyncQueue().isNotEmpty) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'You have unsynced orders. Let them sync first, or they will be lost.';
      });
      return;
    }

    try {
      final scheduledFor = await repo.requestAccountDeletion(
        storeId: auth.currentStore.storeId,
      );
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _scheduledFor = scheduledFor;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'Could not send the request. Please try again.';
      });
    }
  }

  void _signOut() {
    final bloc = context.read<AuthBloc>();
    Navigator.of(context).popUntil((route) => route.isFirst);
    bloc.add(LogoutRequestedEvent());
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthBloc>().state;
    if (auth is! AuthenticatedState) return const SizedBox.shrink();

    if (_scheduledFor != null) return _buildDone(auth);

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: const Text('Delete account', style: AppTextStyles.h2),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: _buildForm(auth),
        ),
      ),
    );
  }

  Widget _buildForm(AuthenticatedState auth) {
    final isOwner = auth.isOwner;
    final canSubmit =
        !_submitting &&
        (!isOwner || _confirmController.text.trim() == 'DELETE');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isOwner) ...[
          _notice(
            icon: Icons.warning_amber_rounded,
            color: AppColors.danger,
            background: AppColors.dangerBg,
            border: AppColors.dangerBorder,
            text:
                "All your orders, customers, staff, and store data will be "
                "wiped out. This can't be undone once the "
                "$accountDeletionGraceDays days are over.",
          ),
          const SizedBox(height: 18),
          const Text('What gets deleted', style: AppTextStyles.h3),
          const SizedBox(height: 8),
          for (final line in const [
            'Your owner account and every outlet',
            'All orders, invoices, and payment records',
            'Customers, services, and expenses',
            'All staff accounts under your store',
          ])
            _bullet(line),
        ] else ...[
          AppInset(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Mobile number', style: AppTextStyles.hint),
                const SizedBox(height: 2),
                Text(auth.user.phone, style: AppTextStyles.h3),
                const SizedBox(height: 6),
                const Text(
                  'This is the only personal data we hold about you.',
                  style: AppTextStyles.hint,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _notice(
            icon: Icons.info_outline,
            color: AppColors.warning,
            background: AppColors.warningBg,
            border: AppColors.warningBorder,
            text:
                'Your data will be deleted automatically within '
                '$accountDeletionGraceDays days.',
          ),
        ],
        const SizedBox(height: 18),
        const Text('What happens next', style: AppTextStyles.h3),
        const SizedBox(height: 8),
        _bullet("Today: you are signed out and can't use the app."),
        _bullet(
          'Within $accountDeletionGraceDays days: '
          '${isOwner ? 'everything is permanently wiped.' : 'your mobile number is permanently deleted.'}',
        ),
        _bullet(
          'Changed your mind? Sign in again within '
          '$accountDeletionGraceDays days to restore your account.',
        ),
        if (!isOwner) ...[
          const SizedBox(height: 6),
          const Text(
            'Orders you handled stay with your store, which owns them.',
            style: AppTextStyles.hint,
          ),
        ],
        if (isOwner) ...[
          const SizedBox(height: 18),
          AppTextField(
            label: 'Type DELETE to confirm',
            hintText: 'DELETE',
            controller: _confirmController,
            enabled: !_submitting,
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 14),
          Text(
            _error!,
            style: const TextStyle(
              fontFamily: AppTextStyles.fontBody,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.danger,
            ),
          ),
        ],
        const SizedBox(height: 22),
        PrimaryButton(
          label: isOwner ? 'Delete store and all data' : 'Delete my account',
          backgroundColor: AppColors.danger,
          isLoading: _submitting,
          loadingLabel: 'Sending…',
          onPressed: canSubmit ? () => _submit(auth) : null,
        ),
        const SizedBox(height: 12),
        SecondaryButton(
          label: isOwner ? 'Cancel' : 'Keep my account',
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  /// Same full-screen layout as the restore screen shown after the next sign-in.
  Widget _buildDone(AuthenticatedState auth) {
    final isOwner = auth.isOwner;
    final date = DateFormatter.parseCalendarDate(_scheduledFor);
    final days = date?.difference(DateTime.now()).inDays.clamp(0, 100000);
    final what = isOwner ? 'Your store and all its data' : 'Your mobile number';

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Center(
                child: Container(
                  width: 68,
                  height: 68,
                  decoration: const BoxDecoration(
                    color: AppColors.warningBg,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.schedule,
                    size: 32,
                    color: AppColors.warning,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Deletion requested',
                style: AppTextStyles.h1,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                '$what will be permanently deleted on '
                '${DateFormatter.formatFull(_scheduledFor)}.',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.mutedText,
                ),
                textAlign: TextAlign.center,
              ),
              if (days != null) ...[
                const SizedBox(height: 16),
                Text(
                  '$days ${days == 1 ? 'day' : 'days'} left to restore',
                  style: AppTextStyles.hint.copyWith(
                    color: AppColors.warning,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 20),
              AppInset(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Text(
                  'Changed your mind? Sign in again before then and '
                  '${isOwner ? 'everything comes back as you left it.' : 'you can use the app again as before.'}',
                  style: AppTextStyles.hint.copyWith(
                    color: AppColors.mutedText,
                  ),
                ),
              ),
              const Spacer(),
              PrimaryButton(label: 'Sign out', onPressed: _signOut),
            ],
          ),
        ),
      ),
    );
  }

  Widget _notice({
    required IconData icon,
    required Color color,
    required Color background,
    required Color border,
    required String text,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.hint.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 7, right: 10),
            child: Icon(Icons.circle, size: 5, color: AppColors.mutedText),
          ),
          Expanded(child: Text(text, style: AppTextStyles.hint)),
        ],
      ),
    );
  }
}
