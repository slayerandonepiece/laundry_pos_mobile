import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:myshop/core/constants/app_colors.dart';
import 'package:myshop/core/theme/text_styles.dart';
import 'package:myshop/features/owner/bloc/owner_bloc.dart';
import 'package:myshop/features/owner/bloc/owner_event.dart';
import 'package:myshop/features/owner/bloc/owner_state.dart';
import 'package:myshop/shared/widgets/app_button.dart';
import 'package:myshop/shared/widgets/app_text_field.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _showPasswords = false;
  String? _error;

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<OwnerBloc, OwnerState>(
      listenWhen: (prev, curr) =>
          curr.messageSection == OwnerSection.profile &&
          (curr.error != null || curr.actionMessage != null),
      listener: (context, state) {
        if (state.messageSection != OwnerSection.profile) return;
        if (state.actionMessage != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.actionMessage!),
              backgroundColor: AppColors.success,
              behavior: SnackBarBehavior.floating,
            ),
          );
          Navigator.pop(context);
        }
        if (state.error != null) {
          setState(() => _error = state.error);
        }
      },
      builder: (context, state) {
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
              'Change password',
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
              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.dangerBg,
                    border: Border.all(color: AppColors.dangerBorder),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: AppColors.danger,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.danger,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              AppTextField(
                label: 'CURRENT PASSWORD',
                hint: 'Enter your current password',
                obscureText: !_showPasswords,
                controller: _currentPasswordController,
              ),
              const SizedBox(height: 14),

              AppTextField(
                label: 'NEW PASSWORD',
                hint: 'At least 8 characters',
                obscureText: !_showPasswords,
                controller: _newPasswordController,
              ),
              const SizedBox(height: 14),

              AppTextField(
                label: 'CONFIRM NEW PASSWORD',
                hint: 'Re-enter new password',
                obscureText: !_showPasswords,
                controller: _confirmPasswordController,
              ),
              const SizedBox(height: 12),

              // Show passwords toggle
              Row(
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      value: _showPasswords,
                      activeColor: AppColors.primary,
                      onChanged: (val) {
                        setState(() => _showPasswords = val ?? false);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () {
                      setState(() => _showPasswords = !_showPasswords);
                    },
                    child: const Text(
                      'Show passwords',
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontBody,
                        fontSize: 14,
                        color: AppColors.text,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              PrimaryButton(
                label: 'Update password',
                isLoading: state.loading.contains(OwnerSection.profile),
                onPressed: () {
                  final current = _currentPasswordController.text;
                  final newPass = _newPasswordController.text;
                  final confirm = _confirmPasswordController.text;

                  if (current.isEmpty || newPass.isEmpty) {
                    setState(() => _error = 'Please fill in all fields.');
                    return;
                  }
                  if (newPass.length < 8) {
                    setState(
                      () => _error =
                          'New password must be at least 8 characters.',
                    );
                    return;
                  }
                  if (newPass != confirm) {
                    setState(() => _error = "New passwords do not match.");
                    return;
                  }

                  setState(() => _error = null);
                  context.read<OwnerBloc>().add(
                    ChangePasswordSubmittedEvent(
                      currentPassword: current,
                      newPassword: newPass,
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
