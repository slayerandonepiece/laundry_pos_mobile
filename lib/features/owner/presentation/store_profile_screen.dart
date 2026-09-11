import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:myshop/core/constants/app_colors.dart';
import 'package:myshop/core/theme/text_styles.dart';
import 'package:myshop/features/owner/bloc/owner_bloc.dart';
import 'package:myshop/features/owner/bloc/owner_event.dart';
import 'package:myshop/features/owner/bloc/owner_state.dart';
import 'package:myshop/shared/widgets/app_button.dart';
import 'package:myshop/shared/widgets/app_inset.dart';
import 'package:myshop/shared/widgets/app_text_field.dart';

class StoreProfileScreen extends StatefulWidget {
  const StoreProfileScreen({super.key});

  @override
  State<StoreProfileScreen> createState() => _StoreProfileScreenState();
}

class _StoreProfileScreenState extends State<StoreProfileScreen> {
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    context.read<OwnerBloc>().add(LoadStoreProfileEvent());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<OwnerBloc, OwnerState>(
      listener: (context, state) {
        if (state.storeProfile != null && !_isInitialized) {
          _nameController.text = state.storeProfile!.storeName;
          _addressController.text = state.storeProfile!.address;
          _phoneController.text = state.storeProfile!.phone;
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
              'Store profile',
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
              AppInset(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.receipt_long_outlined,
                      size: 20,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'This information appears at the top of all printed and digital customer invoices.',
                        style: AppTextStyles.hint.copyWith(
                          color: AppColors.text,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              AppTextField(
                label: 'STORE NAME',
                hint: 'e.g. Chinnappanahalli Laundry',
                controller: _nameController,
              ),
              const SizedBox(height: 14),

              AppTextField(
                label: 'STORE ADDRESS',
                hint: 'No. 12, Main Road, Bengaluru',
                controller: _addressController,
              ),
              const SizedBox(height: 14),

              AppTextField(
                label: 'STORE PHONE',
                hint: '+91 80 4123 9900',
                keyboardType: TextInputType.phone,
                controller: _phoneController,
              ),
              const SizedBox(height: 24),

              PrimaryButton(
                label: 'Save profile',
                isLoading: state.isLoading,
                onPressed: () {
                  final name = _nameController.text.trim();
                  final address = _addressController.text.trim();
                  final phone = _phoneController.text.trim();

                  if (name.isEmpty) return;

                  context.read<OwnerBloc>().add(
                    UpdateStoreProfileEvent(
                      storeName: name,
                      address: address,
                      phone: phone,
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
