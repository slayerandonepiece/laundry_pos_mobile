import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../auth/data/auth_repository.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final TextEditingController _currentPasswordController =
      TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  bool _isSubmitting = false;
  bool _isClearing = false;
  String? _errorMessage;
  String? _successMessage;

  @override
  void initState() {
    super.initState();
    _currentPasswordController.addListener(_onInputChanged);
    _newPasswordController.addListener(_onInputChanged);
    _confirmPasswordController.addListener(_onInputChanged);
  }

  void _onInputChanged() {
    if (_isClearing) return;
    if (_errorMessage != null || _successMessage != null) {
      setState(() {
        _errorMessage = null;
        _successMessage = null;
      });
    } else {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final current = _currentPasswordController.text.trim();
    final newPass = _newPasswordController.text;
    final confirm = _confirmPasswordController.text;

    if (current.isEmpty) {
      setState(() => _errorMessage = 'Please enter your current password.');
      return;
    }
    if (newPass.length < 8) {
      setState(
        () => _errorMessage = 'Password must be at least 8 characters long.',
      );
      return;
    }
    if (newPass != confirm) {
      setState(() => _errorMessage = "Passwords don't match. Please re-enter.");
      return;
    }
    if (newPass == current) {
      setState(
        () => _errorMessage =
            'New password must be different from current password.',
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final repo = context.read<AuthRepository>();
      await repo.changePassword(current, newPass);
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _successMessage = 'Password updated successfully.';
      });
      _isClearing = true;
      _currentPasswordController.clear();
      _newPasswordController.clear();
      _confirmPasswordController.clear();
      _isClearing = false;
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst(
        RegExp(r'^(Exception|ApiException):\s*'),
        '',
      );
      setState(() {
        _isSubmitting = false;
        _errorMessage = msg.isNotEmpty
            ? msg
            : 'Could not update your password. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = _currentPasswordController.text;
    final newPass = _newPasswordController.text;
    final confirm = _confirmPasswordController.text;
    final isEightChars = newPass.length >= 8;
    final canSubmit =
        current.isNotEmpty &&
        isEightChars &&
        confirm.isNotEmpty &&
        !_isSubmitting;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.text),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Change password', style: AppTextStyles.h3),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: AppColors.border, height: 1),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Update your password', style: AppTextStyles.h2),
            const SizedBox(height: 6),
            const Text(
              'Choose a strong password of at least 8 characters.',
              style: AppTextStyles.hint,
            ),
            const SizedBox(height: 22),

            // Error banner
            if (_errorMessage != null) ...[
              Container(
                decoration: BoxDecoration(
                  color: AppColors.dangerBg,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: AppColors.dangerBorder),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 13,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 18,
                      color: AppColors.danger,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(
                          fontFamily: AppTextStyles.fontBody,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.danger,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
            ],

            // Success banner
            if (_successMessage != null) ...[
              Container(
                decoration: BoxDecoration(
                  color: AppColors.successBg,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(
                    color: AppColors.success.withValues(alpha: 0.3),
                  ),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 13,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle_outline,
                      size: 18,
                      color: AppColors.success,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _successMessage!,
                        style: const TextStyle(
                          fontFamily: AppTextStyles.fontBody,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.success,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
            ],

            // Current Password
            AppTextField(
              label: 'Current password',
              hintText: 'Enter your current password',
              controller: _currentPasswordController,
              obscureText: _obscureCurrent,
              enabled: !_isSubmitting,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureCurrent
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 20,
                  color: AppColors.mutedText,
                ),
                onPressed: () =>
                    setState(() => _obscureCurrent = !_obscureCurrent),
              ),
            ),
            const SizedBox(height: 16),

            // New Password
            AppTextField(
              label: 'New password',
              hintText: 'Enter new password',
              controller: _newPasswordController,
              obscureText: _obscureNew,
              enabled: !_isSubmitting,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureNew
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 20,
                  color: AppColors.mutedText,
                ),
                onPressed: () => setState(() => _obscureNew = !_obscureNew),
              ),
            ),
            const SizedBox(height: 8),

            // 8-character requirement row
            Row(
              children: [
                Icon(
                  isEightChars
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  size: 14,
                  color: isEightChars ? AppColors.success : AppColors.mutedText,
                ),
                const SizedBox(width: 8),
                Text(
                  'At least 8 characters',
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontBody,
                    fontSize: 12.5,
                    color: isEightChars
                        ? AppColors.success
                        : AppColors.mutedText,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Confirm Password
            AppTextField(
              label: 'Confirm new password',
              hintText: 'Re-enter new password',
              controller: _confirmPasswordController,
              obscureText: _obscureConfirm,
              enabled: !_isSubmitting,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureConfirm
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 20,
                  color: AppColors.mutedText,
                ),
                onPressed: () =>
                    setState(() => _obscureConfirm = !_obscureConfirm),
              ),
            ),
            const SizedBox(height: 28),

            // Submit Button
            PrimaryButton(
              label: 'Change password',
              isLoading: _isSubmitting,
              onPressed: canSubmit ? _submit : null,
            ),
          ],
        ),
      ),
    );
  }
}
