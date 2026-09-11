import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_inset.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../bloc/auth_bloc.dart';
import '../bloc/auth_event.dart';
import '../bloc/auth_state.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  @override
  void initState() {
    super.initState();
    _newPasswordController.addListener(() => setState(() {}));
    _confirmPasswordController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _submit() {
    context.read<AuthBloc>().add(
      SetPasswordSubmittedEvent(
        newPassword: _newPasswordController.text,
        confirmPassword: _confirmPasswordController.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    final effectiveTopInset = topInset > 0 ? topInset : 59.0;
    final newPass = _newPasswordController.text;
    final confirmPass = _confirmPasswordController.text;
    final isEightChars = newPass.length >= 8;
    final canSubmit = isEightChars && confirmPass.isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: BlocBuilder<AuthBloc, AuthState>(
        builder: (context, state) {
          final isLoading = state is AuthLoadingState;
          String? errorMessage;
          if (state is MustChangePasswordState) {
            errorMessage = state.errorMessage;
          }

          return Column(
            children: [
              SizedBox(height: effectiveTopInset),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 26,
                    vertical: 26,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Lock icon tile
                      Container(
                        width: 54,
                        height: 54,
                        alignment: Alignment.centerLeft,
                        child: Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            color: AppColors.primaryTint,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.lock_outline_rounded,
                              size: 28,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text('Set a new password', style: AppTextStyles.h1),
                      const SizedBox(height: 9),
                      Text(
                        'Your store owner reset your password. Choose one only you know — you will use it from now on.',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.mutedText,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Error banner if mismatch or failure
                      if (errorMessage != null) ...[
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
                                  errorMessage,
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
                        const SizedBox(height: 20),
                      ],

                      AppTextField(
                        label: 'New password',
                        hintText: 'Enter new password',
                        controller: _newPasswordController,
                        obscureText: _obscureNew,
                        enabled: !isLoading,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureNew
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            size: 20,
                            color: AppColors.mutedText,
                          ),
                          onPressed: () =>
                              setState(() => _obscureNew = !_obscureNew),
                        ),
                      ),
                      const SizedBox(height: 18),
                      AppTextField(
                        label: 'Confirm new password',
                        hintText: 'Re-enter it',
                        controller: _confirmPasswordController,
                        obscureText: _obscureConfirm,
                        enabled: !isLoading,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureConfirm
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            size: 20,
                            color: AppColors.mutedText,
                          ),
                          onPressed: () => setState(
                            () => _obscureConfirm = !_obscureConfirm,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Checklist Inset
                      AppInset(
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Icon(
                                  isEightChars
                                      ? Icons.check_circle_rounded
                                      : Icons.radio_button_unchecked,
                                  size: 16,
                                  color: isEightChars
                                      ? AppColors.success
                                      : AppColors.controlBorder,
                                ),
                                const SizedBox(width: 9),
                                Text(
                                  'At least 8 characters',
                                  style: TextStyle(
                                    fontFamily: AppTextStyles.fontBody,
                                    fontSize: 12,
                                    fontWeight: isEightChars
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                    color: isEightChars
                                        ? AppColors.success
                                        : AppColors.mutedText,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 9),
                            const Row(
                              children: [
                                Icon(
                                  Icons.radio_button_unchecked,
                                  size: 16,
                                  color: AppColors.controlBorder,
                                ),
                                SizedBox(width: 9),
                                Text(
                                  'Different from your temporary password',
                                  style: TextStyle(
                                    fontFamily: AppTextStyles.fontBody,
                                    fontSize: 12,
                                    color: AppColors.mutedText,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Bottom footer button
              Container(
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  border: Border(
                    top: BorderSide(color: AppColors.border, width: 1),
                  ),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 24,
                ),
                child: PrimaryButton(
                  label: 'Save and continue',
                  isLoading: isLoading,
                  onPressed: canSubmit && !isLoading ? _submit : null,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
