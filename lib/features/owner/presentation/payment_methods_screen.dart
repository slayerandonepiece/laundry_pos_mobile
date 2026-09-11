import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:myshop/core/constants/app_colors.dart';
import 'package:myshop/core/theme/text_styles.dart';
import 'package:myshop/features/owner/bloc/owner_bloc.dart';
import 'package:myshop/features/owner/bloc/owner_event.dart';
import 'package:myshop/features/owner/bloc/owner_state.dart';
import 'package:myshop/shared/widgets/app_card.dart';

class PaymentMethodsScreen extends StatefulWidget {
  const PaymentMethodsScreen({super.key});

  @override
  State<PaymentMethodsScreen> createState() => _PaymentMethodsScreenState();
}

class _PaymentMethodsScreenState extends State<PaymentMethodsScreen> {
  @override
  void initState() {
    super.initState();
    context.read<OwnerBloc>().add(LoadPaymentMethodsEvent());
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<OwnerBloc, OwnerState>(
      builder: (context, state) {
        final methods = state.paymentMethods;

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
              'Payment methods',
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
          body: RefreshIndicator(
            onRefresh: () async {
              context.read<OwnerBloc>().add(LoadPaymentMethodsEvent());
            },
            child: ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: methods.length,
              separatorBuilder: (_, _) => const SizedBox(height: 11),
              itemBuilder: (context, index) {
                final method = methods[index];
                return AppCard(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(
                        method.type.toUpperCase() == 'UPI'
                            ? Icons.qr_code_scanner_outlined
                            : Icons.payments_outlined,
                        size: 24,
                        color: method.active
                            ? AppColors.primary
                            : AppColors.mutedText,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              method.name,
                              style: const TextStyle(
                                fontFamily: AppTextStyles.fontBody,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppColors.text,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(method.type, style: AppTextStyles.hint),
                          ],
                        ),
                      ),
                      Switch(
                        value: method.active,
                        activeThumbColor: AppColors.primary,
                        onChanged: (val) {
                          context.read<OwnerBloc>().add(
                            TogglePaymentMethodEvent(
                              id: method.id,
                              active: val,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}
