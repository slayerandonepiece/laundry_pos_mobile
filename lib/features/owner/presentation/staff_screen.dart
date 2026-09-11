import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:myshop/core/constants/app_colors.dart';
import 'package:myshop/core/theme/text_styles.dart';
import 'package:myshop/features/owner/bloc/owner_bloc.dart';
import 'package:myshop/features/owner/bloc/owner_event.dart';
import 'package:myshop/features/owner/bloc/owner_state.dart';
import 'package:myshop/shared/widgets/app_button.dart';
import 'package:myshop/shared/widgets/app_card.dart';
import 'package:myshop/shared/widgets/app_text_field.dart';
import 'package:myshop/shared/widgets/empty_state.dart';

class StaffScreen extends StatefulWidget {
  const StaffScreen({super.key});

  @override
  State<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends State<StaffScreen> {
  @override
  void initState() {
    super.initState();
    context.read<OwnerBloc>().add(LoadStaffEvent());
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
        final staff = state.staff;

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
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Staff',
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontDisplay,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${staff.length} ${staff.length == 1 ? "member" : "members"}',
                  style: AppTextStyles.hint,
                ),
              ],
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: IconButton(
                  icon: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: const Icon(Icons.add, color: Colors.white, size: 20),
                  ),
                  onPressed: () => _showAddStaffDialog(context),
                ),
              ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Container(color: AppColors.border, height: 1),
            ),
          ),
          body: RefreshIndicator(
            onRefresh: () async {
              context.read<OwnerBloc>().add(LoadStaffEvent());
            },
            child: staff.isEmpty
                ? ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 40),
                        child: EmptyState(
                          icon: Icons.people_outline,
                          title: 'No staff members yet',
                          subtitle:
                              'Add employees to take sales and manage orders.',
                        ),
                      ),
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(20),
                    itemCount: staff.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 11),
                    itemBuilder: (context, index) {
                      final member = staff[index];
                      return AppCard(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: member.active
                                    ? AppColors.primaryTint
                                    : AppColors.neutralBg,
                              ),
                              child: Center(
                                child: Text(
                                  member.name.isNotEmpty
                                      ? member.name[0].toUpperCase()
                                      : 'S',
                                  style: TextStyle(
                                    fontFamily: AppTextStyles.fontDisplay,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: member.active
                                        ? AppColors.primary
                                        : AppColors.mutedText,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 13),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    member.name,
                                    style: const TextStyle(
                                      fontFamily: AppTextStyles.fontBody,
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.text,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '@${member.username}',
                                    style: AppTextStyles.hint,
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: member.active,
                              activeThumbColor: AppColors.primary,
                              onChanged: (val) {
                                context.read<OwnerBloc>().add(
                                  ToggleStaffActiveEvent(member.id),
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

  void _showAddStaffDialog(BuildContext context) {
    final nameController = TextEditingController();
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 10,
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.controlBorder,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const Text(
              'Add staff member',
              style: TextStyle(
                fontFamily: AppTextStyles.fontDisplay,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 16),
            AppTextField(
              label: 'FULL NAME',
              hint: 'e.g. Ramesh Kumar',
              controller: nameController,
            ),
            const SizedBox(height: 12),
            AppTextField(
              label: 'USERNAME',
              hint: 'e.g. ramesh',
              controller: usernameController,
            ),
            const SizedBox(height: 12),
            AppTextField(
              label: 'TEMPORARY PASSWORD',
              hint: 'At least 8 characters',
              obscureText: true,
              controller: passwordController,
            ),
            const SizedBox(height: 20),
            PrimaryButton(
              label: 'Create staff account',
              onPressed: () {
                final name = nameController.text.trim();
                final username = usernameController.text.trim();
                final password = passwordController.text.trim();

                if (name.isEmpty || username.isEmpty || password.length < 8) {
                  return;
                }

                context.read<OwnerBloc>().add(
                  AddStaffEvent(
                    name: name,
                    username: username,
                    password: password,
                  ),
                );
                Navigator.pop(sheetContext);
              },
            ),
          ],
        ),
      ),
    );
  }
}
