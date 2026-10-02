import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/utils/phone_normalizer.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../orders/data/orders_repository.dart';
import '../bloc/cart_bloc.dart';
import '../bloc/cart_event.dart';
import 'dialogs/discard_order_dialog.dart';
import 'new_sale_browse_screen.dart';

/// Step 1 of the new-order flow: just phone number and name, nothing else —
/// due date and notes keep their sensible defaults (see CartState) rather
/// than asking for them up front.
///
/// "Next" stays disabled until the phone number has been looked up (via the
/// search action on the field) — either a returning customer was found, or
/// the lookup came back empty/failed and the flow proceeds as a new/offline
/// customer. Either outcome unlocks Next; only an un-searched or edited-since
/// -searching phone number blocks it.
class CustomerDetailsScreen extends StatefulWidget {
  const CustomerDetailsScreen({super.key});

  @override
  State<CustomerDetailsScreen> createState() => _CustomerDetailsScreenState();
}

class _CustomerDetailsScreenState extends State<CustomerDetailsScreen> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final FocusNode _phoneFocusNode = FocusNode();
  String? _phoneError;
  bool _isSearching = false;
  bool _hasSearched = false;
  bool _customerFound = false;
  String? _searchedPhone;

  // Indian mobile numbers: 10 digits, first digit 6-9.
  static final RegExp _indianMobileRegex = RegExp(r'^[6-9]\d{9}$');

  @override
  void initState() {
    super.initState();
    final cart = context.read<CartBloc>().state;
    _nameController.text = cart.customerName;
    // Only re-populate the phone field (and treat it as already searched)
    // if we're returning to this screen with the same customer already set
    // up — never a placeholder/sample value.
    if (cart.customerPhone.isNotEmpty) {
      _phoneController.text = cart.customerPhone;
      _searchedPhone = cart.customerPhone;
      _hasSearched = true;
      _customerFound = cart.customerName.isNotEmpty;
    }
    _phoneController.addListener(_onPhoneEdited);
    _phoneFocusNode.addListener(_onPhoneFocusChanged);
  }

  @override
  void dispose() {
    _phoneController.removeListener(_onPhoneEdited);
    _phoneFocusNode.removeListener(_onPhoneFocusChanged);
    _phoneFocusNode.dispose();
    _phoneController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _onPhoneEdited() {
    if (_phoneError != null) {
      setState(() => _phoneError = null);
    }
    // Editing the phone after a search invalidates that search — Next
    // locks again until the (new) number is looked up. Compared normalised,
    // so blur-normalising a searched number doesn't undo the lookup.
    if (_hasSearched &&
        tenDigitPhone(_phoneController.text) != _searchedPhone) {
      setState(() {
        _hasSearched = false;
        _customerFound = false;
      });
    }
  }

  // Raw text is kept while typing; on blur the field is rewritten to its
  // 10-digit form (so a pasted "+91 98765 43210" becomes "9876543210") and
  // anything still invalid shows the inline error.
  void _onPhoneFocusChanged() {
    if (_phoneFocusNode.hasFocus || !mounted) return;
    final phone = _normalisePhone();
    if (phone.isNotEmpty && !_indianMobileRegex.hasMatch(phone)) {
      setState(() => _phoneError = 'Enter a valid 10-digit mobile number');
    }
  }

  /// Replaces the phone text with its normalised 10-digit form — never
  /// truncated — and returns it.
  String _normalisePhone() {
    final phone = tenDigitPhone(_phoneController.text);
    if (phone != _phoneController.text) {
      _phoneController.value = TextEditingValue(
        text: phone,
        selection: TextSelection.collapsed(offset: phone.length),
      );
    }
    return phone;
  }

  Future<void> _searchCustomer() async {
    final phone = _normalisePhone();
    if (!_indianMobileRegex.hasMatch(phone)) {
      setState(() => _phoneError = 'Enter a valid 10-digit mobile number');
      return;
    }

    setState(() {
      _phoneError = null;
      _isSearching = true;
    });

    // Local cache first, then the server if nothing's cached — and if that
    // fails too (offline, unreachable), lookupCustomerName just returns
    // null rather than throwing, so this never blocks the flow.
    final match = await context.read<OrdersRepository>().lookupCustomerName(
      phone,
    );

    if (!mounted) return;
    setState(() {
      _isSearching = false;
      _hasSearched = true;
      _searchedPhone = phone;
      _customerFound = match != null;
      if (match != null && _nameController.text.trim().isEmpty) {
        _nameController.text = match;
      }
    });
  }

  void _proceedToServices() {
    final phone = _normalisePhone();
    final cart = context.read<CartBloc>().state;
    context.read<CartBloc>().add(
      SetCustomerDetailsEvent(
        phone: phone,
        customerName: _nameController.text.trim(),
        dueDate: cart.dueDate,
        notes: cart.notes,
      ),
    );

    Navigator.of(context).push(
      MaterialPageRoute(
        settings: const RouteSettings(name: 'new_order_items'),
        builder: (_) => const NewSaleBrowseScreen(),
      ),
    );
  }

  void _handleBack(BuildContext context) {
    if (_phoneController.text.trim().isNotEmpty ||
        _nameController.text.trim().isNotEmpty) {
      DiscardOrderDialog.show(
        context,
        onDiscard: () {
          Navigator.of(context).pop();
        },
      );
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBack(context);
      },
      child: Scaffold(
        backgroundColor: AppColors.surface,
        body: SafeArea(
          child: Column(
            children: [
              // App Bar
              Container(
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  border: Border(
                    bottom: BorderSide(color: AppColors.border, width: 1),
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close, color: AppColors.text),
                      onPressed: () => _handleBack(context),
                    ),
                    const SizedBox(width: 4),
                    const Text('New order', style: AppTextStyles.h3),
                  ],
                ),
              ),

              // Body
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Who is this order for?',
                        style: AppTextStyles.h2,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'The phone number is required — the invoice goes to it on WhatsApp.',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.mutedText,
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Phone field with +91 prefix and a search action
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text('PHONE NUMBER', style: AppTextStyles.label),
                              const SizedBox(width: 4),
                              const Text(
                                '•',
                                style: TextStyle(
                                  color: AppColors.danger,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Container(
                            height: 54,
                            decoration: BoxDecoration(
                              color: _phoneError != null
                                  ? AppColors.dangerInputBg
                                  : AppColors.surface,
                              borderRadius: BorderRadius.circular(9),
                              border: Border.all(
                                color: _phoneError != null
                                    ? AppColors.dangerInput
                                    : AppColors.controlBorder,
                                width: 1,
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            child: Row(
                              children: [
                                const Text(
                                  '+91',
                                  style: TextStyle(
                                    fontFamily: AppTextStyles.fontBody,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.mutedText,
                                  ),
                                ),
                                Container(
                                  width: 1,
                                  height: 24,
                                  color: AppColors.border,
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                ),
                                Expanded(
                                  child: TextField(
                                    controller: _phoneController,
                                    focusNode: _phoneFocusNode,
                                    keyboardType: TextInputType.phone,
                                    // No digits-only filter or length cap:
                                    // either would mangle a pasted
                                    // "+91 98765 43210". tenDigitPhone
                                    // cleans it on blur/submit.
                                    inputFormatters: [
                                      FilteringTextInputFormatter.allow(
                                        RegExp(r'[\d+\-\s()]'),
                                      ),
                                    ],
                                    style: AppTextStyles.bodyLarge,
                                    decoration: const InputDecoration(
                                      hintText: 'Enter phone number',
                                      border: InputBorder.none,
                                      isDense: true,
                                    ),
                                    onSubmitted: (_) => _searchCustomer(),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                _buildSearchAction(),
                              ],
                            ),
                          ),
                          if (_phoneError != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              _phoneError!,
                              style: const TextStyle(
                                fontFamily: AppTextStyles.fontBody,
                                fontSize: 12,
                                color: AppColors.danger,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ] else if (_hasSearched) ...[
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Icon(
                                  _customerFound
                                      ? Icons.history
                                      : Icons.person_add_alt_1_outlined,
                                  size: 14,
                                  color: AppColors.mutedText,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  _customerFound
                                      ? 'Returning customer — name filled in'
                                      : 'New customer',
                                  style: AppTextStyles.hint,
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),

                      const SizedBox(height: 12),

                      // Customer Name (Optional) — auto-filled for a returning
                      // customer, but always editable.
                      AppTextField(
                        label: 'CUSTOMER NAME · optional',
                        hintText: 'Optional',
                        controller: _nameController,
                      ),
                    ],
                  ),
                ),
              ),

              // Bottom Footer
              Container(
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  border: Border(
                    top: BorderSide(color: AppColors.border, width: 1),
                  ),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                child: PrimaryButton(
                  label: 'Next',
                  onPressed: _hasSearched ? _proceedToServices : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchAction() {
    if (_isSearching) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (_hasSearched) {
      return Icon(
        Icons.check_circle,
        size: 22,
        color: _customerFound ? AppColors.success : AppColors.mutedText,
      );
    }
    return InkWell(
      onTap: _searchCustomer,
      borderRadius: BorderRadius.circular(20),
      child: const Padding(
        padding: EdgeInsets.all(4),
        child: Icon(Icons.search, size: 22, color: AppColors.primary),
      ),
    );
  }
}
