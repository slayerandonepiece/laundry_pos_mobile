import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../bloc/auth_bloc.dart';
import '../bloc/auth_event.dart';
import '../bloc/auth_state.dart';
import 'dialogs/forgot_password_dialog.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _obscurePassword = true;
  String? _usernameError;
  String? _passwordError;

  @override
  void initState() {
    super.initState();
    _usernameController.addListener(() => setState(() {}));
    _passwordController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _submit() {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    setState(() {
      _usernameError = username.isEmpty ? 'Enter your username' : null;
      _passwordError = password.isEmpty ? 'Enter your password' : null;
    });

    if (_usernameError != null || _passwordError != null) {
      return;
    }

    context.read<AuthBloc>().add(
      LoginSubmittedEvent(username: username, password: password),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    final effectiveTopInset = topInset > 0 ? topInset : 59.0;
    final isNotEmpty =
        _usernameController.text.trim().isNotEmpty &&
        _passwordController.text.isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: BlocBuilder<AuthBloc, AuthState>(
        builder: (context, state) {
          final isLoading = state is AuthLoadingState;
          String? bannerError;

          if (state is UnauthenticatedState) {
            if (state.noActiveStore) {
              bannerError = 'Your account is not linked to any active store. Check with your store owner.';
            } else if (state.errorMessage != null) {
              bannerError = state.errorMessage;
            }
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
                      // Header mark and titles
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 54,
                            height: 54,
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.local_laundry_service_rounded,
                                color: Colors.white,
                                size: 30,
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          const Text('Sign in', style: AppTextStyles.h1),
                          const SizedBox(height: 9),
                          Text(
                            'Use the account your store owner created for you.',
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: AppColors.mutedText,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Error Banner (State 2c / 2e)
                      if (bannerError != null) ...[
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
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.error_outline,
                                size: 18,
                                color: AppColors.danger,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  bannerError,
                                  style: const TextStyle(
                                    fontFamily: AppTextStyles.fontBody,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.danger,
                                    height: 1.45,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],

                      // Form Fields
                      AppTextField(
                        label: 'Username',
                        hintText: 'Enter your username',
                        controller: _usernameController,
                        errorText: _usernameError,
                        enabled: !isLoading,
                      ),
                      const SizedBox(height: 18),
                      AppTextField(
                        label: 'Password',
                        hintText: 'Enter your password',
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        errorText: _passwordError,
                        enabled: !isLoading,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            size: 20,
                            color: AppColors.mutedText,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Sign in Button (2a disabled when empty, 2d loading in flight)
                      PrimaryButton(
                        label: 'Sign in',
                        isLoading: isLoading,
                        onPressed: (isNotEmpty && !isLoading) ? _submit : null,
                      ),
                    ],
                  ),
                ),
              ),

              // Footer help text (Interactive Forgot Password affordance)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                child: InkWell(
                  onTap: () => ForgotPasswordDialog.show(context),
                  borderRadius: BorderRadius.circular(8),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                    child: Text(
                      'Forgot your password? Your store owner can reset it for you.',
                      style: AppTextStyles.hint,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
