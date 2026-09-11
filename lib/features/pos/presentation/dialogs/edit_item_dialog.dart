import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/text_styles.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/quantity_formatter.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../bloc/cart_state.dart';

class EditItemDialog extends StatefulWidget {
  final CartItem item;
  final ValueChanged<double> onUpdateQuantity;
  final VoidCallback onRemove;

  const EditItemDialog({
    super.key,
    required this.item,
    required this.onUpdateQuantity,
    required this.onRemove,
  });

  @override
  State<EditItemDialog> createState() => _EditItemDialogState();
}

class _EditItemDialogState extends State<EditItemDialog> {
  late double _quantity;
  late TextEditingController _weightController;

  @override
  void initState() {
    super.initState();
    _quantity = widget.item.quantity;
    _weightController = TextEditingController(
      text: widget.item.product.isWeight
          ? QuantityFormatter.format(_quantity)
          : _quantity.toInt().toString(),
    );
  }

  @override
  void dispose() {
    _weightController.dispose();
    super.dispose();
  }

  void _onWeightChanged(String val) {
    final parsed = double.tryParse(val.trim());
    if (parsed != null && parsed > 0) {
      setState(() {
        _quantity = parsed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.item.product;
    final lineTotal = product.computePrice(_quantity);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: Color.fromRGBO(6, 27, 58, 0.28),
              blurRadius: 44,
              offset: Offset(0, 18),
            ),
          ],
        ),
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(product.name, style: AppTextStyles.h2),
            const SizedBox(height: 6),
            Text(
              product.isWeight
                  ? 'Per kg slab pricing'
                  : 'Per piece · ${CurrencyFormatter.format(product.price)} each',
              style: AppTextStyles.hint,
            ),
            const SizedBox(height: 20),

            // Quantity or Weight Editor
            if (product.isWeight) ...[
              Text('WEIGHT', style: AppTextStyles.label),
              const SizedBox(height: 8),
              Container(
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: AppColors.primary, width: 1.5),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _weightController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'^\d*\.?\d{0,3}'),
                          ),
                        ],
                        style: AppTextStyles.moneyMedium,
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                        ),
                        onChanged: _onWeightChanged,
                      ),
                    ),
                    const Text('kg', style: AppTextStyles.chip),
                  ],
                ),
              ),
            ] else ...[
              Text('QUANTITY', style: AppTextStyles.label),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    iconSize: 28,
                    icon: const Icon(
                      Icons.remove_circle_outline,
                      color: AppColors.primary,
                    ),
                    onPressed: _quantity > 1
                        ? () {
                            setState(() {
                              _quantity -= 1;
                              _weightController.text = _quantity
                                  .toInt()
                                  .toString();
                            });
                          }
                        : null,
                  ),
                  const SizedBox(width: 18),
                  Text(
                    '${_quantity.toInt()} pcs',
                    style: AppTextStyles.moneyLarge.copyWith(fontSize: 26),
                  ),
                  const SizedBox(width: 18),
                  IconButton(
                    iconSize: 28,
                    icon: const Icon(
                      Icons.add_circle,
                      color: AppColors.primary,
                    ),
                    onPressed: () {
                      setState(() {
                        _quantity += 1;
                        _weightController.text = _quantity.toInt().toString();
                      });
                    },
                  ),
                ],
              ),
            ],

            const SizedBox(height: 18),

            // Line total inset
            Container(
              decoration: BoxDecoration(
                color: AppColors.inset,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: AppColors.border),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Line total',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.mutedText,
                    ),
                  ),
                  Text(
                    CurrencyFormatter.format(lineTotal),
                    style: AppTextStyles.moneyMedium.copyWith(fontSize: 18),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Remove from sale destructive option
            InkWell(
              onTap: () {
                Navigator.of(context).pop();
                widget.onRemove();
              },
              borderRadius: BorderRadius.circular(11),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.dangerBg,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: AppColors.dangerBorder),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 15,
                  vertical: 13,
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.delete_outline,
                      size: 20,
                      color: AppColors.danger,
                    ),
                    SizedBox(width: 12),
                    Text(
                      'Remove from sale',
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontBody,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.danger,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 22),

            Row(
              children: [
                Expanded(
                  child: SecondaryButton(
                    label: 'Cancel',
                    height: 48,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: PrimaryButton(
                    label: 'Update',
                    height: 48,
                    onPressed: () {
                      Navigator.of(context).pop();
                      widget.onUpdateQuantity(_quantity);
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
