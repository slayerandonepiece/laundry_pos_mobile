import 'dart:async';

import 'package:flutter/material.dart';
import 'package:myshop/shared/widgets/app_version_text.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/app_assets.dart';
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

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _obscurePassword = true;
  String? _phoneError;
  String? _passwordError;

  late final AnimationController _bannerAnimController;
  late final Animation<Offset> _slideAnimation;
  late final Animation<double> _fadeAnimation;
  Timer? _autoDismissTimer;
  String? _displayedError;
  String? _lastDismissedError;

  @override
  void initState() {
    super.initState();
    _phoneController.addListener(() => setState(() {}));
    _passwordController.addListener(() => setState(() {}));

    _bannerAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, -0.4), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _bannerAnimController,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          ),
        );
    _fadeAnimation = CurvedAnimation(
      parent: _bannerAnimController,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = context.read<AuthBloc>().state;
    _syncErrorFromState(state, isInitial: true);
  }

  @override
  void dispose() {
    _autoDismissTimer?.cancel();
    _bannerAnimController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _syncErrorFromState(AuthState state, {bool isInitial = false}) {
    String? bannerError;
    if (state is UnauthenticatedState) {
      if (state.noActiveStore) {
        bannerError = 'Your account is not linked to any active store. Check with your store owner.';
      } else if (state.errorMessage != null) {
        bannerError = state.errorMessage;
      }
    }

    if (bannerError != null) {
      if (_lastDismissedError == bannerError) {
        return;
      }
      if (_displayedError == bannerError && _bannerAnimController.value > 0) {
        return;
      }
      _autoDismissTimer?.cancel();
      _displayedError = bannerError;
      if (isInitial) {
        _bannerAnimController.value = 1.0;
      } else {
        _bannerAnimController.forward(from: 0.0);
      }
      _autoDismissTimer = Timer(const Duration(seconds: 6), () {
        if (mounted) {
          _dismissBanner();
        }
      });
      if (!isInitial && mounted) {
        setState(() {});
      }
    } else {
      if (_displayedError != null) {
        _dismissBanner();
      }
    }
  }

  void _dismissBanner() {
    _autoDismissTimer?.cancel();
    _lastDismissedError = _displayedError;
    _bannerAnimController.reverse().then((_) {
      if (mounted) {
        setState(() {
          _displayedError = null;
        });
      }
    });
  }

  void _submit() {
    final phone = _phoneController.text.trim();
    final password = _passwordController.text;

    setState(() {
      _phoneError = phone.isEmpty ? 'Enter your phone number' : null;
      _passwordError = password.isEmpty ? 'Enter your password' : null;
    });

    if (_phoneError != null || _passwordError != null) {
      return;
    }

    _lastDismissedError = null;
    context.read<AuthBloc>().add(
      LoginSubmittedEvent(phone: phone, password: password),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    final effectiveTopInset = topInset > 0 ? topInset : 59.0;
    final isNotEmpty =
        _phoneController.text.trim().isNotEmpty &&
        _passwordController.text.isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: BlocConsumer<AuthBloc, AuthState>(
        listener: (context, state) {
          _syncErrorFromState(state);
        },
        builder: (context, state) {
          final isLoading = state is AuthLoadingState;

          return Stack(
            children: [
              Column(
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
                              ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: Image.asset(
                                  AppAssets.logo,
                                  width: 54,
                                  height: 54,
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

                          // Form Fields (no inline error shifting layout)
                          AppTextField(
                            label: 'Phone number',
                            hintText: 'Enter your phone number',
                            keyboardType: TextInputType.phone,
                            controller: _phoneController,
                            errorText: _phoneError,
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
                            onPressed: (isNotEmpty && !isLoading)
                                ? _submit
                                : null,
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
                        padding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 10,
                        ),
                        child: Text(
                          'Forgot your password? Your store owner can reset it for you.',
                          style: AppTextStyles.hint,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: AppVersionText(),
                  ),
                ],
              ),

              // Top-anchored Overlay Error Banner
              if (_displayedError != null)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      child: SlideTransition(
                        position: _slideAnimation,
                        child: FadeTransition(
                          opacity: _fadeAnimation,
                          child: Material(
                            color: Colors.transparent,
                            child: Container(
                              decoration: BoxDecoration(
                                color: AppColors.dangerBg,
                                borderRadius: BorderRadius.circular(11),
                                border: Border.all(
                                  color: AppColors.dangerBorder,
                                ),
                                boxShadow: [
                                  const BoxShadow(
                                    color: Color(0x0F000000),
                                    blurRadius: 10,
                                    offset: Offset(0, 4),
                                  ),
                                ],
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 13,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Padding(
                                    padding: EdgeInsets.only(top: 2),
                                    child: Icon(
                                      Icons.error_outline,
                                      size: 18,
                                      color: AppColors.danger,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      _displayedError!,
                                      style: const TextStyle(
                                        fontFamily: AppTextStyles.fontBody,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.danger,
                                        height: 1.45,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  GestureDetector(
                                    key: const Key('login_error_dismiss'),
                                    onTap: _dismissBanner,
                                    behavior: HitTestBehavior.opaque,
                                    child: const Padding(
                                      padding: EdgeInsets.all(2),
                                      child: Icon(
                                        Icons.close,
                                        size: 18,
                                        color: AppColors.danger,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
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
