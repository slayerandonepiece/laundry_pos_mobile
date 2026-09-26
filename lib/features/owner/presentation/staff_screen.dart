import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:myshop/core/constants/app_colors.dart';
import 'package:myshop/core/theme/text_styles.dart';
import 'package:myshop/core/utils/idempotency.dart';
import 'package:myshop/features/owner/bloc/owner_bloc.dart';
import 'package:myshop/features/owner/bloc/owner_event.dart';
import 'package:myshop/features/owner/bloc/owner_state.dart';
import 'package:myshop/features/owner/data/models/staff_model.dart';
import 'package:myshop/shared/widgets/app_button.dart';
import 'package:myshop/shared/widgets/app_card.dart';
import 'package:myshop/shared/widgets/app_text_field.dart';
import 'package:myshop/shared/widgets/empty_state.dart';
import 'package:myshop/shared/widgets/sync_status_bar.dart';

class StaffScreen extends StatefulWidget {
  const StaffScreen({super.key});

  @override
  State<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends State<StaffScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    context.read<OwnerBloc>().add(LoadStaffEvent());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showAddStaffDialog(BuildContext context) {
    final bloc = context.read<OwnerBloc>();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            BlocProvider.value(value: bloc, child: const AddStaffScreen()),
      ),
    );
  }

  void _showEditStaffDialog(BuildContext context, StaffMember member) {
    final bloc = context.read<OwnerBloc>();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BlocProvider.value(
          value: bloc,
          child: EditStaffScreen(member: member),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<OwnerBloc, OwnerState>(
      listenWhen: (prev, curr) =>
          curr.messageSection == OwnerSection.staff &&
          (curr.error != null || curr.actionMessage != null),
      listener: (context, state) {
        if (state.messageSection != OwnerSection.staff) return;
        if (state.actionMessage != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.actionMessage!),
              backgroundColor: AppColors.success,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        if (state.error != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.error!),
              backgroundColor: AppColors.danger,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      },
      builder: (context, state) {
        final staff = state.staff;
        final filteredStaff = staff.where((member) {
          if (_searchQuery.isEmpty) return true;
          final query = _searchQuery.toLowerCase();
          return member.name.toLowerCase().contains(query) ||
              member.username.toLowerCase().contains(query);
        }).toList();

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
              IconButton(
                icon: const Icon(
                  Icons.refresh_rounded,
                  color: AppColors.mutedText,
                  size: 20,
                ),
                tooltip: 'Refresh',
                onPressed: () {
                  context.read<OwnerBloc>().add(LoadStaffEvent(refresh: true));
                },
              ),
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
          body: Column(
            children: [
              SyncStatusBar(
                onSyncNow: () {
                  context.read<OwnerBloc>().add(LoadStaffEvent(refresh: true));
                },
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async {
                    final done = Completer<void>();
                    context.read<OwnerBloc>().add(
                      LoadStaffEvent(refresh: true, done: done),
                    );
                    await done.future;
                  },
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(20),
                    children: [
                      // 1. Subtitle matching web
                      const Text(
                        'Employees can use Sales and manage Orders.',
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontBody,
                          fontSize: 13.5,
                          color: AppColors.mutedText,
                        ),
                      ),
                      const SizedBox(height: 14),

                      // 2. Search box
                      Container(
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          border: Border.all(color: AppColors.controlBorder),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 13),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.search,
                              size: 19,
                              color: AppColors.mutedText,
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: TextField(
                                controller: _searchController,
                                style: const TextStyle(
                                  fontFamily: AppTextStyles.fontBody,
                                  fontSize: 14,
                                  color: AppColors.text,
                                ),
                                decoration: const InputDecoration(
                                  hintText: 'Search name or username...',
                                  hintStyle: TextStyle(
                                    fontFamily: AppTextStyles.fontBody,
                                    fontSize: 14,
                                    color: AppColors.faintText,
                                  ),
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                ),
                                onChanged: (val) {
                                  setState(() => _searchQuery = val);
                                },
                              ),
                            ),
                            if (_searchController.text.isNotEmpty)
                              InkWell(
                                onTap: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                                child: const Padding(
                                  padding: EdgeInsets.all(4),
                                  child: Icon(
                                    Icons.close,
                                    size: 16,
                                    color: AppColors.mutedText,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // 3. Employee cards or empty state
                      if (state.loading.contains(OwnerSection.staff) &&
                          staff.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 40),
                          child: Center(
                            child: CircularProgressIndicator(
                              color: AppColors.primary,
                            ),
                          ),
                        )
                      else if (staff.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 40),
                          child: EmptyState(
                            icon: Icons.people_outline,
                            title: 'No staff members yet',
                            subtitle: 'Add employees to take sales and manage orders.',
                          ),
                        )
                      else if (filteredStaff.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 40),
                          child: EmptyState(
                            icon: Icons.search_off,
                            title: 'No staff found',
                            subtitle: 'No members match "$_searchQuery".',
                          ),
                        )
                      else
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: filteredStaff.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 11),
                          itemBuilder: (context, index) {
                            final member = filteredStaff[index];
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
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
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
                                          '@${member.username} · Employee',
                                          style: AppTextStyles.hint,
                                        ),
                                      ],
                                    ),
                                  ),
                                  OutlinedButton(
                                    onPressed: () =>
                                        _showEditStaffDialog(context, member),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      minimumSize: Size.zero,
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      side: const BorderSide(
                                        color: AppColors.controlBorder,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                    ),
                                    child: const Text(
                                      'Edit',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
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

                      // 4. Footer note matching web
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Center(
                          child: Text(
                            'Deactivated employees cannot sign in until reactivated.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: AppTextStyles.fontBody,
                              fontSize: 12.5,
                              color: AppColors.mutedText,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class AddStaffScreen extends StatefulWidget {
  const AddStaffScreen({super.key});

  @override
  State<AddStaffScreen> createState() => _AddStaffScreenState();
}

class _AddStaffScreenState extends State<AddStaffScreen> {
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  late final String _idempotencyKey = IdempotencyKeyGenerator.generate();
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _save() {
    final name = _nameController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();

    if (name.isEmpty || username.isEmpty || password.length < 8) {
      setState(() {
        if (name.isEmpty) {
          _errorMessage = 'Full name is required';
        } else if (username.isEmpty) {
          _errorMessage = 'Username is required';
        } else {
          _errorMessage = 'Password must be at least 8 characters';
        }
      });
      return;
    }

    context.read<OwnerBloc>().add(
      AddStaffEvent(
        name: name,
        username: username,
        password: password,
        idempotencyKey: _idempotencyKey,
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
          'Add staff member',
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
              label: 'FULL NAME',
              hint: 'e.g. Ramesh Kumar',
              controller: _nameController,
            ),
            const SizedBox(height: 14),
            AppTextField(
              label: 'USERNAME',
              hint: 'e.g. ramesh',
              controller: _usernameController,
            ),
            const SizedBox(height: 14),
            AppTextField(
              label: 'TEMPORARY PASSWORD',
              hint: 'At least 8 characters',
              obscureText: true,
              controller: _passwordController,
            ),
            const SizedBox(height: 24),
            PrimaryButton(label: 'Create staff account', onPressed: _save),
          ],
        ),
      ),
    );
  }
}

class EditStaffScreen extends StatefulWidget {
  final StaffMember member;

  const EditStaffScreen({super.key, required this.member});

  @override
  State<EditStaffScreen> createState() => _EditStaffScreenState();
}

class _EditStaffScreenState extends State<EditStaffScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _usernameController;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.member.name);
    _usernameController = TextEditingController(text: widget.member.username);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  void _save() {
    final name = _nameController.text.trim();
    final username = _usernameController.text.trim();

    if (name.isEmpty || username.isEmpty) {
      setState(() {
        if (name.isEmpty) {
          _errorMessage = 'Full name is required';
        } else {
          _errorMessage = 'Username is required';
        }
      });
      return;
    }

    context.read<OwnerBloc>().add(
      UpdateStaffEvent(
        employeeId: widget.member.id,
        name: name,
        username: username,
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
          'Edit staff member',
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
              label: 'FULL NAME',
              hint: 'e.g. Ramesh Kumar',
              controller: _nameController,
            ),
            const SizedBox(height: 14),
            AppTextField(
              label: 'USERNAME',
              hint: 'e.g. ramesh',
              controller: _usernameController,
            ),
            const SizedBox(height: 24),
            PrimaryButton(label: 'Save changes', onPressed: _save),
          ],
        ),
      ),
    );
  }
}
