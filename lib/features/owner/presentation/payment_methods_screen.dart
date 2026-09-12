import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:myshop/core/constants/app_colors.dart';
import 'package:myshop/core/theme/text_styles.dart';
import 'package:myshop/features/owner/bloc/owner_bloc.dart';
import 'package:myshop/features/owner/bloc/owner_event.dart';
import 'package:myshop/features/owner/bloc/owner_state.dart';
import 'package:myshop/features/owner/data/models/payment_method_model.dart';
import 'package:myshop/shared/widgets/app_button.dart';
import 'package:myshop/shared/widgets/app_card.dart';
import 'package:myshop/shared/widgets/app_text_field.dart';

class PaymentMethodsScreen extends StatefulWidget {
  const PaymentMethodsScreen({super.key});

  @override
  State<PaymentMethodsScreen> createState() => _PaymentMethodsScreenState();
}

class _PaymentMethodsScreenState extends State<PaymentMethodsScreen> {
  final _newMethodController = TextEditingController();

  @override
  void initState() {
    super.initState();
    context.read<OwnerBloc>().add(LoadPaymentMethodsEvent());
  }

  @override
  void dispose() {
    _newMethodController.dispose();
    super.dispose();
  }

  void _showRenameMethodDialog(
    BuildContext context,
    StorePaymentMethod method,
  ) {
    final bloc = context.read<OwnerBloc>();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BlocProvider.value(
          value: bloc,
          child: RenamePaymentMethodScreen(method: method),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<OwnerBloc, OwnerState>(
      listener: (context, state) {
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
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // Existing payment methods list
                if (methods.isNotEmpty) ...[
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
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
                                  Row(
                                    children: [
                                      Text(
                                        method.type,
                                        style: AppTextStyles.hint,
                                      ),
                                      const SizedBox(width: 10),
                                      TextButton(
                                        onPressed: () =>
                                            _showRenameMethodDialog(
                                              context,
                                              method,
                                            ),
                                        style: TextButton.styleFrom(
                                          padding: EdgeInsets.zero,
                                          minimumSize: Size.zero,
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        ),
                                        child: const Text(
                                          'Rename',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.primary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
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
                  const SizedBox(height: 20),
                ],

                // Inline "Add payment method" card matching web
                AppCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Add payment method',
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontDisplay,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text,
                        ),
                      ),
                      const SizedBox(height: 12),
                      AppTextField(
                        label: 'METHOD NAME',
                        hint: 'e.g. PhonePe QR or Card Machine',
                        controller: _newMethodController,
                      ),
                      const SizedBox(height: 14),
                      PrimaryButton(
                        label: 'Add method',
                        isLoading: state.isLoading,
                        onPressed: () {
                          final name = _newMethodController.text.trim();
                          if (name.isEmpty) return;
                          context.read<OwnerBloc>().add(
                            AddPaymentMethodEvent(name),
                          );
                          _newMethodController.clear();
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class RenamePaymentMethodScreen extends StatefulWidget {
  final StorePaymentMethod method;

  const RenamePaymentMethodScreen({super.key, required this.method});

  @override
  State<RenamePaymentMethodScreen> createState() =>
      _RenamePaymentMethodScreenState();
}

class _RenamePaymentMethodScreenState extends State<RenamePaymentMethodScreen> {
  late final TextEditingController _nameController;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.method.name);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _errorMessage = 'Payment method name is required');
      return;
    }

    context.read<OwnerBloc>().add(
      RenamePaymentMethodEvent(
        id: widget.method.id,
        name: name,
      ),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
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
          'Rename payment method',
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
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.dangerBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(
                    fontFamily: AppTextStyles.fontBody,
                    fontSize: 13,
                    color: AppColors.danger,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 14),
            ],
            AppTextField(
              label: 'PAYMENT METHOD NAME',
              hint: 'e.g. Google Pay UPI',
              controller: _nameController,
            ),
            const SizedBox(height: 24),
            PrimaryButton(
              label: 'Save changes',
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }
}
