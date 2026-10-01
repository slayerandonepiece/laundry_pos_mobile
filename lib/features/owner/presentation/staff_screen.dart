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
import 'package:myshop/features/owner/presentation/outlet_assignment_field.dart';
import 'package:myshop/features/shell/bloc/outlet_scope_cubit.dart';
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
              member.phone.toLowerCase().contains(query);
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
                                  hintText: 'Search name or phone...',
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
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
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
                                              fontFamily:
                                                  AppTextStyles.fontDisplay,
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
                                                fontFamily:
                                                    AppTextStyles.fontBody,
                                                fontSize: 14.5,
                                                fontWeight: FontWeight.w700,
                                                color: AppColors.text,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              member.phone,
                                              style: AppTextStyles.hint,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      SizedBox(
                                        width: 64,
                                        child: SecondaryButton(
                                          label: 'Edit',
                                          height: AppButtonHeight.inline,
                                          textColor: AppColors.primary,
                                          onPressed: () => _showEditStaffDialog(
                                            context,
                                            member,
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
                                  // Outlets on their own full-width line: the
                                  // name column beside Edit and the switch is
                                  // too narrow to show more than one outlet.
                                  if (member.hasNoOutletAccess) ...[
                                    const SizedBox(height: 10),
                                    const _NoOutletBadge(),
                                  ] else if (_outletSummary(member)
                                      .isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      _outletSummary(member),
                                      style: AppTextStyles.hint,
                                    ),
                                  ],
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

/// "Main Road (default) · Lake View" — which outlets an employee works in.
String _outletSummary(StaffMember member) {
  // Never a blank label or a dangling " · ": fall back to the id, and skip an
  // outlet that has neither.
  final outlets = [
    for (final o in member.outlets ?? const <StaffOutlet>[])
      if (o.name.trim().isNotEmpty || o.id.trim().isNotEmpty) o,
  ];
  return outlets
      .map((o) {
        final label = o.name.trim().isNotEmpty ? o.name.trim() : o.id.trim();
        return outlets.length > 1 && o.id == member.defaultOutletId
            ? '$label (default)'
            : label;
      })
      .join(' · ');
}

/// Shown when the server says an employee has no outlet: they can sign in
/// but have nowhere to work until the owner assigns one.
class _NoOutletBadge extends StatelessWidget {
  const _NoOutletBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.warningBg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text(
        'No outlet access — assign one',
        style: TextStyle(
          fontFamily: AppTextStyles.fontBody,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: AppColors.warning,
        ),
      ),
    );
  }
}

/// The outlets this owner can hand out: the active ones from sign-in.
List<AssignableOutlet> _assignableOutlets(BuildContext context) {
  final scope = context.read<OutletScopeCubit?>()?.state;
  if (scope == null) return const [];
  return [
    for (final o in scope.allowed)
      if (o.status.toUpperCase() == 'ACTIVE')
        AssignableOutlet(id: o.id, name: o.displayName, code: o.outletCode),
  ];
}

class AddStaffScreen extends StatefulWidget {
  const AddStaffScreen({super.key});

  @override
  State<AddStaffScreen> createState() => _AddStaffScreenState();
}

class _AddStaffScreenState extends State<AddStaffScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  late final String _idempotencyKey = IdempotencyKeyGenerator.generate();
  String? _errorMessage;

  late final List<AssignableOutlet> _outlets = _assignableOutlets(context);
  late Set<String> _selectedOutlets = _outlets.length == 1
      ? {_outlets.first.id}
      : <String>{};
  late String? _defaultOutlet = _outlets.length == 1 ? _outlets.first.id : null;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _save() {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final password = _passwordController.text.trim();

    if (name.isEmpty || phone.isEmpty || password.length < 8) {
      setState(() {
        if (name.isEmpty) {
          _errorMessage = 'Full name is required';
        } else if (phone.isEmpty) {
          _errorMessage = 'Phone number is required';
        } else {
          _errorMessage = 'Password must be at least 8 characters';
        }
      });
      return;
    }

    // An employee with no outlet can sign in but has nowhere to work.
    if (_outlets.isNotEmpty && _selectedOutlets.isEmpty) {
      setState(
        () => _errorMessage = 'Choose at least one outlet they can work in',
      );
      return;
    }

    context.read<OwnerBloc>().add(
      AddStaffEvent(
        name: name,
        phone: phone,
        password: password,
        idempotencyKey: _idempotencyKey,
        outletIds: _outlets.isEmpty ? null : _selectedOutlets.toList(),
        defaultOutletId: _outlets.isEmpty ? null : _defaultOutlet,
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
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
                label: 'PHONE NUMBER',
                hint: 'e.g. 9876543210',
                keyboardType: TextInputType.phone,
                controller: _phoneController,
              ),
              const SizedBox(height: 14),
              AppTextField(
                label: 'TEMPORARY PASSWORD',
                hint: 'At least 8 characters',
                obscureText: true,
                controller: _passwordController,
              ),
              if (_outlets.isNotEmpty) ...[
                const SizedBox(height: 14),
                OutletAssignmentField(
                  outlets: _outlets,
                  selected: _selectedOutlets,
                  defaultId: _defaultOutlet,
                  onChanged: (selected, defaultId) => setState(() {
                    _selectedOutlets = selected;
                    _defaultOutlet = defaultId;
                    _errorMessage = null;
                  }),
                ),
              ],
              const SizedBox(height: 24),
              PrimaryButton(label: 'Create staff account', onPressed: _save),
            ],
          ),
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
  late final TextEditingController _phoneController;
  String? _errorMessage;

  // The owner's outlets plus any the employee already has that the owner's
  // list doesn't show, so saving never silently drops one.
  late final List<AssignableOutlet> _outlets = () {
    final options = _assignableOutlets(context);
    final known = options.map((o) => o.id).toSet();
    return [
      ...options,
      for (final o in widget.member.outlets ?? const <StaffOutlet>[])
        if (!known.contains(o.id))
          AssignableOutlet(id: o.id, name: o.name.isEmpty ? o.id : o.name),
    ];
  }();
  late Set<String> _selectedOutlets = {
    for (final o in widget.member.outlets ?? const <StaffOutlet>[]) o.id,
  };
  late String? _defaultOutlet = widget.member.defaultOutletId;
  bool _outletsTouched = false;

  /// Assignments are only editable once they are known: a list cached before
  /// they were kept could otherwise be "corrected" blind.
  bool get _canEditOutlets =>
      _outlets.isNotEmpty && widget.member.outlets != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.member.name);
    _phoneController = TextEditingController(text: widget.member.phone);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _save() {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();

    if (name.isEmpty || phone.isEmpty) {
      setState(() {
        if (name.isEmpty) {
          _errorMessage = 'Full name is required';
        } else {
          _errorMessage = 'Phone number is required';
        }
      });
      return;
    }

    final sendOutlets = _canEditOutlets && _outletsTouched;
    if (sendOutlets && _selectedOutlets.isEmpty) {
      setState(
        () => _errorMessage = 'Choose at least one outlet they can work in',
      );
      return;
    }

    // Outlets are only sent when changed, so an ordinary name or phone edit
    // leaves the employee's assignments exactly as they are.
    context.read<OwnerBloc>().add(
      UpdateStaffEvent(
        employeeId: widget.member.id,
        name: name,
        phone: phone,
        outletIds: sendOutlets ? _selectedOutlets.toList() : null,
        defaultOutletId: sendOutlets ? _defaultOutlet : null,
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
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
                label: 'PHONE NUMBER',
                hint: 'e.g. 9876543210',
                keyboardType: TextInputType.phone,
                controller: _phoneController,
              ),
              if (widget.member.hasNoOutletAccess) ...[
                const SizedBox(height: 14),
                const _NoOutletBadge(),
              ],
              if (_canEditOutlets) ...[
                const SizedBox(height: 14),
                OutletAssignmentField(
                  outlets: _outlets,
                  selected: _selectedOutlets,
                  defaultId: _defaultOutlet,
                  onChanged: (selected, defaultId) => setState(() {
                    _selectedOutlets = selected;
                    _defaultOutlet = defaultId;
                    _outletsTouched = true;
                    _errorMessage = null;
                  }),
                ),
              ],
              const SizedBox(height: 24),
              PrimaryButton(label: 'Save changes', onPressed: _save),
            ],
          ),
        ),
      ),
    );
  }
}
