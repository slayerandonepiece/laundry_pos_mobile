import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:myshop/core/constants/app_colors.dart';
import 'package:myshop/core/theme/text_styles.dart';
import 'package:myshop/core/utils/currency_formatter.dart';
import 'package:myshop/features/owner/data/owner_repository.dart';
import 'package:myshop/features/pos/data/models/product_model.dart';
import 'package:myshop/features/pos/data/pos_repository.dart';
import 'package:myshop/shared/widgets/app_button.dart';
import 'package:myshop/shared/widgets/app_card.dart';
import 'package:myshop/shared/widgets/app_text_field.dart';
import 'package:myshop/shared/widgets/status_pill.dart';

class ServicesScreen extends StatefulWidget {
  const ServicesScreen({super.key});

  @override
  State<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends State<ServicesScreen> {
  List<Product> _products = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadServices();
  }

  Future<void> _loadServices() async {
    setState(() => _isLoading = true);
    try {
      final list = await context.read<PosRepository>().listProducts();
      setState(() {
        _products = list;
        _isLoading = false;
      });
    } catch (_) {
      setState(() => _isLoading = false);
    }
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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Services',
              style: TextStyle(
                fontFamily: AppTextStyles.fontDisplay,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${_products.length} services configured',
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
              onPressed: () => _showAddServiceDialog(context),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: AppColors.border, height: 1),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : RefreshIndicator(
              onRefresh: _loadServices,
              child: ListView.separated(
                padding: const EdgeInsets.all(20),
                itemCount: _products.length,
                separatorBuilder: (_, _) => const SizedBox(height: 11),
                itemBuilder: (context, index) {
                  final product = _products[index];
                  return AppCard(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                product.name,
                                style: const TextStyle(
                                  fontFamily: AppTextStyles.fontBody,
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.text,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Row(
                                children: [
                                  StatusPill(
                                    label: product.isWeight
                                        ? 'Per kg'
                                        : 'Per piece',
                                    variant: product.isWeight
                                        ? PillVariant.inProgress
                                        : PillVariant.neutral,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    product.category,
                                    style: AppTextStyles.hint,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              CurrencyFormatter.format(product.price),
                              style: const TextStyle(
                                fontFamily: AppTextStyles.fontDisplay,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: AppColors.text,
                              ),
                            ),
                            if (product.slabs.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                '${product.slabs.length} slabs',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primary,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
    );
  }

  void _showAddServiceDialog(BuildContext context) {
    final nameController = TextEditingController();
    final priceController = TextEditingController();
    String category = 'wash';
    String unit = 'PIECE';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return Container(
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 10,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
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
                  'Add service',
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontDisplay,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 16),
                AppTextField(
                  label: 'SERVICE NAME',
                  hint: 'e.g. Silk Saree Dry Clean',
                  controller: nameController,
                ),
                const SizedBox(height: 12),
                AppTextField(
                  label: 'BASE PRICE (₹)',
                  hint: 'e.g. 150',
                  keyboardType: TextInputType.number,
                  controller: priceController,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: category,
                        decoration: InputDecoration(
                          labelText: 'CATEGORY',
                          labelStyle: AppTextStyles.fieldLabel,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        items: ['wash', 'dry clean', 'iron', 'premium']
                            .map(
                              (c) => DropdownMenuItem(
                                value: c,
                                child: Text(c.toUpperCase()),
                              ),
                            )
                            .toList(),
                        onChanged: (v) =>
                            setDialogState(() => category = v ?? 'wash'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: unit,
                        decoration: InputDecoration(
                          labelText: 'UNIT TYPE',
                          labelStyle: AppTextStyles.fieldLabel,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: 'PIECE',
                            child: Text('Per piece'),
                          ),
                          const DropdownMenuItem(
                            value: 'WEIGHT',
                            child: Text('Per kg'),
                          ),
                        ],
                        onChanged: (v) =>
                            setDialogState(() => unit = v ?? 'PIECE'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                PrimaryButton(
                  label: 'Create service',
                  onPressed: () async {
                    final name = nameController.text.trim();
                    final priceInRupees =
                        double.tryParse(priceController.text.trim()) ?? 0;
                    final priceInPaise = (priceInRupees * 100).round();
                    if (name.isEmpty || priceInPaise <= 0) return;

                    Navigator.pop(sheetContext);
                    try {
                      await context.read<OwnerRepository>().createProduct(
                        name: name,
                        category: category,
                        unit: unit,
                        price: priceInPaise,
                      );
                      _loadServices();
                    } catch (_) {}
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
