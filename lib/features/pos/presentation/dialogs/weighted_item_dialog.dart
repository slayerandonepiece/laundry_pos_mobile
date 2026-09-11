import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/text_styles.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/quantity_formatter.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../data/models/product_model.dart';

/// Bottom sheet shown immediately when the user taps "Add" on a weighted (per-kg) product.
/// Uses showModalBottomSheet with isScrollControlled=true so it slides above the keyboard
/// without overflowing. The weight field starts empty; price updates live as user types.
class WeightedItemDialog extends StatefulWidget {
  final Product product;

  /// Called with the entered weight (> 0) when the user taps "Add to sale".
  final ValueChanged<double> onAdd;

  /// If provided, pre-fills the weight field (used when editing an existing cart entry).
  final double? initialWeight;

  const WeightedItemDialog({
    super.key,
    required this.product,
    required this.onAdd,
    this.initialWeight,
  });

  @override
  State<WeightedItemDialog> createState() => _WeightedItemDialogState();

  /// Convenience method — uses a bottom sheet so keyboard avoidance works correctly.
  static Future<void> show(
    BuildContext context, {
    required Product product,
    required ValueChanged<double> onAdd,
    double? initialWeight,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true, // sheet resizes when keyboard appears
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.scrim.withValues(alpha: 0.42),
      builder: (_) => WeightedItemDialog(
        product: product,
        onAdd: onAdd,
        initialWeight: initialWeight,
      ),
    );
  }
}

class _WeightedItemDialogState extends State<WeightedItemDialog> {
  final TextEditingController _controller = TextEditingController();
  double? _weight; // null = empty / invalid
  bool _showError = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialWeight != null && widget.initialWeight! > 0) {
      _weight = widget.initialWeight;
      _controller.text = QuantityFormatter.format(widget.initialWeight!);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged(String val) {
    final trimmed = val.trim();
    final parsed = double.tryParse(trimmed);
    setState(() {
      _weight = (parsed != null && parsed > 0) ? parsed : null;
      _showError = false;
    });
  }

  void _onAdd() {
    if (_weight == null) {
      setState(() => _showError = true);
      return;
    }
    Navigator.of(context).pop();
    widget.onAdd(_weight!);
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final computedPrice = _weight != null ? product.computePrice(_weight!) : 0;
    // viewInsets.bottom = keyboard height; padding.bottom = safe area
    final bottomPadding =
        MediaQuery.of(context).viewInsets.bottom +
        MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Color.fromRGBO(6, 27, 58, 0.22),
            blurRadius: 40,
            offset: Offset(0, -8),
          ),
        ],
      ),
      child: SingleChildScrollView(
        // Pushes content above the keyboard
        padding: EdgeInsets.only(
          left: 22,
          right: 22,
          top: 20,
          bottom: bottomPadding + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        style: AppTextStyles.h2,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Enter weight to calculate price',
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontBody,
                          fontSize: 13,
                          color: AppColors.mutedText,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F0FE),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Per kg',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontBody,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A56DB),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 22),

            // Weight input
            Text('ENTER WEIGHT', style: AppTextStyles.label),
            const SizedBox(height: 8),
            Container(
              height: 60,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _showError ? AppColors.danger : AppColors.primary,
                  width: 1.8,
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'^\d*\.?\d{0,3}'),
                        ),
                      ],
                      style: const TextStyle(
                        fontFamily: AppTextStyles.fontDisplay,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: AppColors.text,
                      ),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        hintText: '0',
                        hintStyle: TextStyle(
                          fontFamily: AppTextStyles.fontDisplay,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: AppColors.mutedText.withValues(alpha: 0.4),
                        ),
                      ),
                      onChanged: _onTextChanged,
                      onSubmitted: (_) => _onAdd(),
                    ),
                  ),
                  const Text(
                    'kg',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontDisplay,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.mutedText,
                    ),
                  ),
                ],
              ),
            ),
            if (_showError) ...[
              const SizedBox(height: 6),
              const Text(
                'Please enter a valid weight greater than 0',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.danger,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],

            const SizedBox(height: 16),

            // Live price display
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                color: _weight != null
                    ? const Color(0xFFF0F7FF)
                    : AppColors.inset,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _weight != null
                      ? const Color(0xFFBFD9F8)
                      : AppColors.border,
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Amount',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.mutedText,
                        ),
                      ),
                      if (_weight != null)
                        Text(
                          QuantityFormatter.formatWeight(_weight!),
                          style: const TextStyle(
                            fontFamily: AppTextStyles.fontBody,
                            fontSize: 12,
                            color: AppColors.mutedText,
                          ),
                        ),
                    ],
                  ),
                  Text(
                    CurrencyFormatter.format(computedPrice),
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontDisplay,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: _weight != null
                          ? AppColors.primary
                          : AppColors.mutedText,
                    ),
                  ),
                ],
              ),
            ),

            // Slab price breakup
            if (product.slabs.isNotEmpty) ...[
              const SizedBox(height: 16),
              _buildSlabBreakup(product),
            ],

            const SizedBox(height: 22),

            // Action buttons — always visible above keyboard
            Row(
              children: [
                Expanded(
                  child: SecondaryButton(
                    label: 'Cancel',
                    height: 50,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: PrimaryButton(
                    label: 'Add to sale',
                    height: 50,
                    onPressed: _onAdd,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlabBreakup(Product product) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'PRICE BREAKDOWN',
          style: TextStyle(
            fontFamily: AppTextStyles.fontBody,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: AppColors.mutedText,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AppColors.inset,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              // Header row
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 9,
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Up to weight',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.mutedText,
                        ),
                      ),
                    ),
                    const Text(
                      'Flat price',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.mutedText,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: AppColors.border),
              // Slab rows
              ...product.slabs.asMap().entries.map((entry) {
                final i = entry.key;
                final slab = entry.value;
                final isActive =
                    _weight != null &&
                    product.computePrice(_weight!) == slab.price;
                return Column(
                  children: [
                    Container(
                      color: isActive
                          ? const Color(0xFFEBF3FF)
                          : Colors.transparent,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                if (isActive)
                                  const Padding(
                                    padding: EdgeInsets.only(right: 6),
                                    child: Icon(
                                      Icons.arrow_right_alt,
                                      size: 16,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                Text(
                                  'Up to ${slab.limit.toInt()} kg',
                                  style: TextStyle(
                                    fontFamily: AppTextStyles.fontBody,
                                    fontSize: 13,
                                    fontWeight: isActive
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: isActive
                                        ? AppColors.primary
                                        : AppColors.text,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            CurrencyFormatter.format(slab.price),
                            style: TextStyle(
                              fontFamily: AppTextStyles.fontDisplay,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: isActive
                                  ? AppColors.primary
                                  : AppColors.text,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (i < product.slabs.length - 1)
                      const Divider(
                        height: 1,
                        color: AppColors.border,
                        indent: 14,
                        endIndent: 14,
                      ),
                  ],
                );
              }),
              // Extra row (if above all slabs)
              if (product.extra > 0) ...[
                const Divider(height: 1, color: AppColors.border),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Above ${product.slabs.last.limit.toInt()} kg',
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontBody,
                            fontSize: 13,
                            fontWeight:
                                (_weight != null &&
                                    _weight! > product.slabs.last.limit)
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color:
                                (_weight != null &&
                                    _weight! > product.slabs.last.limit)
                                ? AppColors.primary
                                : AppColors.text,
                          ),
                        ),
                      ),
                      Text(
                        '+ ${CurrencyFormatter.format(product.extra)}/kg',
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontDisplay,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color:
                              (_weight != null &&
                                  _weight! > product.slabs.last.limit)
                              ? AppColors.primary
                              : AppColors.text,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
