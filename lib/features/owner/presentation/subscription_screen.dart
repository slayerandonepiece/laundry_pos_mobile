import 'package:myshop/shared/widgets/app_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:myshop/core/constants/app_colors.dart';
import 'package:myshop/core/theme/text_styles.dart';
import 'package:myshop/features/auth/bloc/auth_bloc.dart';
import 'package:myshop/features/auth/bloc/auth_state.dart';
import 'package:myshop/features/auth/data/models/user_model.dart';
import 'package:myshop/features/owner/presentation/plan_status_helper.dart';
import 'package:myshop/shared/widgets/app_card.dart';
import 'package:myshop/shared/widgets/section_header.dart';

class SubscriptionScreen extends StatelessWidget {
  const SubscriptionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthBloc>().state;
    StoreSummary? store;

    if (authState is AuthenticatedState) {
      store = authState.currentStore;
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
          'Subscription',
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader(title: 'PLAN STATUS'),
            const SizedBox(height: 8),
            _buildPlanStatusCard(store),
            const SizedBox(height: 24),
            const SectionHeader(title: 'BILLING'),
            const SizedBox(height: 8),
            _buildBillingHistoryCard(context),
          ],
        ),
      ),
    );
  }

  Widget _buildPlanStatusCard(StoreSummary? store) {
    final planStatus = resolvePlanStatus(store);

    if (planStatus.isUnavailable) {
      return AppCard(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Icon(Icons.info_outline, size: 22, color: AppColors.mutedText),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Plan status unavailable',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontBody,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    "Plan status isn't available right now.",
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.mutedText,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final Color titleColor;
    final Color subtitleColor;

    if (planStatus.isWarning) {
      titleColor = AppColors.warning;
      subtitleColor = AppColors.warning;
    } else if (planStatus.isSuccess) {
      titleColor = AppColors.success;
      subtitleColor = AppColors.success;
    } else {
      titleColor = AppColors.text;
      subtitleColor = AppColors.mutedText;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: planStatus.bgColor,
        border: Border.all(color: planStatus.borderColor),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(planStatus.icon, size: 24, color: planStatus.textColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  planStatus.title,
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontBody,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: titleColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  planStatus.subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    color: subtitleColor,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBillingHistoryCard(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.receipt_long_outlined,
                size: 20,
                color: AppColors.mutedText,
              ),
              SizedBox(width: 8),
              Text(
                'Billing history',
                style: TextStyle(
                  fontFamily: AppTextStyles.fontBody,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            "Invoice downloads aren't available in the app yet.",
            style: TextStyle(
              fontSize: 13,
              color: AppColors.mutedText,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          SecondaryButton(
            label: 'Contact support',
            icon: const Icon(
              Icons.help_outline,
              size: 16,
              color: AppColors.primary,
            ),
            height: AppButtonHeight.inline,
            textColor: AppColors.primary,
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Contact support at support@klenpos.com'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
