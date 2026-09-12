import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:myshop/core/constants/app_colors.dart';
import 'package:myshop/core/theme/text_styles.dart';
import 'package:myshop/features/auth/bloc/auth_bloc.dart';
import 'package:myshop/features/auth/bloc/auth_state.dart';
import 'package:myshop/features/owner/bloc/owner_bloc.dart';
import 'package:myshop/features/owner/bloc/owner_event.dart';
import 'package:myshop/features/owner/bloc/owner_state.dart';
import 'package:myshop/shared/widgets/app_button.dart';
import 'package:myshop/shared/widgets/app_card.dart';
import 'package:myshop/shared/widgets/app_text_field.dart';

class OwnerProfileScreen extends StatefulWidget {
  const OwnerProfileScreen({super.key});

  @override
  State<OwnerProfileScreen> createState() => _OwnerProfileScreenState();
}

class _OwnerProfileScreenState extends State<OwnerProfileScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    context.read<OwnerBloc>().add(LoadStoreProfileEvent());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthBloc>().state;
    String fallbackName = 'Owner';
    String username = 'owner';
    String role = 'Store Owner';

    if (authState is AuthenticatedState) {
      fallbackName = authState.user.name.isNotEmpty
          ? authState.user.name
          : authState.user.username;
      username = authState.user.username;
      role = authState.isOwner ? 'Store Owner' : 'Staff Member';
    }

    return BlocConsumer<OwnerBloc, OwnerState>(
      listener: (context, state) {
        if (state.storeProfile != null && !_isInitialized) {
          _nameController.text = state.storeProfile!.name.isNotEmpty
              ? state.storeProfile!.name
              : fallbackName;
          _phoneController.text = state.storeProfile!.phone;
          _emailController.text = state.storeProfile!.email;
          _isInitialized = true;
        }
        if (state.actionMessage != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.actionMessage!),
              backgroundColor: AppColors.success,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      },
      builder: (context, state) {
        final displayName = _nameController.text.isNotEmpty
            ? _nameController.text
            : fallbackName;

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
              'Your details',
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
              Center(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: const BoxDecoration(
                    color: AppColors.primaryTint,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      displayName.isNotEmpty
                          ? displayName[0].toUpperCase()
                          : 'O',
                      style: const TextStyle(
                        fontFamily: AppTextStyles.fontDisplay,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Editable fields
              AppTextField(
                label: 'FULL NAME',
                hint: 'e.g. Ramesh Kumar',
                controller: _nameController,
              ),
              const SizedBox(height: 14),

              AppTextField(
                label: 'PHONE',
                hint: '+91 98765 43210',
                keyboardType: TextInputType.phone,
                controller: _phoneController,
              ),
              const SizedBox(height: 14),

              AppTextField(
                label: 'EMAIL',
                hint: 'owner@example.com',
                keyboardType: TextInputType.emailAddress,
                controller: _emailController,
              ),
              const SizedBox(height: 16),

              // Read-only account info
              AppCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildRow('USERNAME', '@$username'),
                    const Divider(color: AppColors.border, height: 20),
                    _buildRow('ROLE', role),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              PrimaryButton(
                label: 'Save changes',
                isLoading: state.isLoading,
                onPressed: () {
                  final name = _nameController.text.trim();
                  final phone = _phoneController.text.trim();
                  final email = _emailController.text.trim();

                  if (name.isEmpty) return;

                  context.read<OwnerBloc>().add(
                    UpdateStoreProfileEvent(
                      storeName: state.storeProfile?.storeName ?? '',
                      address: state.storeProfile?.address ?? '',
                      phone: phone,
                      name: name,
                      email: email,
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

  Widget _buildRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppTextStyles.fieldLabel),
        Text(
          value,
          style: const TextStyle(
            fontFamily: AppTextStyles.fontBody,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.text,
          ),
        ),
      ],
    );
  }
}
