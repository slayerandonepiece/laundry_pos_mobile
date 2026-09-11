import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:myshop/core/constants/app_colors.dart';
import 'package:myshop/core/theme/text_styles.dart';
import 'package:myshop/features/auth/bloc/auth_bloc.dart';
import 'package:myshop/features/auth/bloc/auth_state.dart';
import 'package:myshop/shared/widgets/app_card.dart';

class OwnerProfileScreen extends StatelessWidget {
  const OwnerProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthBloc>().state;
    String name = 'Owner';
    String username = 'owner';
    String role = 'Store Owner';

    if (authState is AuthenticatedState) {
      name = authState.user.name.isNotEmpty
          ? authState.user.name
          : authState.user.username;
      username = authState.user.username;
      role = authState.isOwner ? 'Store Owner' : 'Staff Member';
    }

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
                  name.isNotEmpty ? name[0].toUpperCase() : 'O',
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

          AppCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildRow('FULL NAME', name),
                const Divider(color: AppColors.border, height: 20),
                _buildRow('USERNAME', '@$username'),
                const Divider(color: AppColors.border, height: 20),
                _buildRow('ROLE', role),
              ],
            ),
          ),
        ],
      ),
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
