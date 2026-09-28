import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/quantity_formatter.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/status_pill.dart';
import '../../../shared/widgets/sync_status_bar.dart';
import '../bloc/cart_bloc.dart';
import '../bloc/cart_event.dart';
import '../bloc/cart_state.dart';
import '../data/models/product_model.dart';
import 'checkout_screen.dart';
import 'dialogs/clear_cart_dialog.dart';
import 'dialogs/discard_order_dialog.dart';
import 'dialogs/edit_item_dialog.dart';
import 'dialogs/weighted_item_dialog.dart';

/// Step 2 of the new-order flow: browse services and build the cart. Reached
/// only from CustomerDetailsScreen (step 1) — customer details are already
/// set on CartBloc by the time this screen shows.
class NewSaleBrowseScreen extends StatefulWidget {
  const NewSaleBrowseScreen({super.key});

  @override
  State<NewSaleBrowseScreen> createState() => _NewSaleBrowseScreenState();
}

class _NewSaleBrowseScreenState extends State<NewSaleBrowseScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    context.read<CartBloc>().add(LoadCatalogEvent());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refreshCatalog(BuildContext context) async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    final bloc = context.read<CartBloc>();
    bloc.add(RefreshCatalogEvent());
    try {
      await bloc.stream.firstWhere((s) => !s.isLoading);
    } finally {
      if (mounted) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  void _handleBack(BuildContext context) {
    final cart = context.read<CartBloc>().state;
    if (cart.hasItems) {
      DiscardOrderDialog.show(
        context,
        onDiscard: () {
          context.read<CartBloc>().add(ResetSaleEvent());
          Navigator.of(context).popUntil((route) => route.isFirst);
        },
      );
      return;
    }
    Navigator.of(context).pop();
  }

  void _openEditDialog(BuildContext context, CartItem item) {
    if (item.product.isWeight) {
      // Weighted items use the dedicated dialog with live price calc & slab breakup
      WeightedItemDialog.show(
        context,
        product: item.product,
        initialWeight:
            item.quantity, // Pre-fill with the currently entered weight
        onAdd: (newWeight) {
          context.read<CartBloc>().add(
            UpdateItemQuantityEvent(
              productId: item.product.id,
              quantity: newWeight,
            ),
          );
        },
      );
      return;
    }
    showDialog(
      context: context,
      barrierColor: AppColors.scrim.withValues(alpha: 0.42),
      builder: (_) => EditItemDialog(
        item: item,
        onUpdateQuantity: (newQty) {
          context.read<CartBloc>().add(
            UpdateItemQuantityEvent(
              productId: item.product.id,
              quantity: newQty,
            ),
          );
        },
        onRemove: () {
          context.read<CartBloc>().add(
            RemoveItemFromCartEvent(item.product.id),
          );
        },
      ),
    );
  }

  void _openClearCartDialog(BuildContext context, CartState state) {
    showDialog(
      context: context,
      barrierColor: AppColors.scrim.withValues(alpha: 0.42),
      builder: (_) => ClearCartDialog(
        itemCount: state.totalItemCount,
        totalAmount: state.totalAmount,
        onClear: () {
          context.read<CartBloc>().add(ClearCartEvent());
        },
      ),
    );
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
              // App Bar (Step 2 of 3)
              Container(
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  border: Border(
                    bottom: BorderSide(color: AppColors.border, width: 1),
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(8, 8, 20, 16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.arrow_back,
                            color: AppColors.text,
                          ),
                          onPressed: () => _handleBack(context),
                        ),
                        const SizedBox(width: 4),
                        const Text('Add services', style: AppTextStyles.h3),
                        const Spacer(),
                        if (_isRefreshing)
                          const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.primary,
                              ),
                            ),
                          )
                        else
                          IconButton(
                            icon: const Icon(
                              Icons.refresh,
                              color: AppColors.text,
                            ),
                            tooltip: 'Refresh catalog',
                            onPressed: () => _refreshCatalog(context),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Search box
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
                              style: AppTextStyles.bodyMedium,
                              decoration: const InputDecoration(
                                hintText: 'Search services...',
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
                                context.read<CartBloc>().add(
                                  SearchQueryChangedEvent(val),
                                );
                              },
                            ),
                          ),
                          if (_searchController.text.isNotEmpty)
                            InkWell(
                              onTap: () {
                                _searchController.clear();
                                context.read<CartBloc>().add(
                                  SearchQueryChangedEvent(''),
                                );
                              },
                              child: const Icon(
                                Icons.close,
                                size: 18,
                                color: AppColors.mutedText,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Live Sync Status Banner
              SyncStatusBar(onSyncNow: () => _refreshCatalog(context)),

              // Products List
              Expanded(
                child: BlocBuilder<CartBloc, CartState>(
                  builder: (context, state) {
                    if (state.isLoading && state.allProducts.isEmpty) {
                      return const Center(
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      );
                    }

                    final products = state.filteredProducts;
                    if (products.isEmpty) {
                      return const EmptyState(
                        icon: Icon(
                          Icons.inventory_2_outlined,
                          color: AppColors.primary,
                          size: 30,
                        ),
                        title: 'No services found',
                        description:
                            'Try adjusting your search or category filter.',
                      );
                    }

                    return ListView.separated(
                      padding: const EdgeInsets.all(20),
                      itemCount: products.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 11),
                      itemBuilder: (context, index) {
                        final product = products[index];
                        final cartItem = state.items[product.id];
                        final isAdded = cartItem != null;

                        return _buildProductRow(
                          context,
                          product: product,
                          cartItem: cartItem,
                          isAdded: isAdded,
                        );
                      },
                    );
                  },
                ),
              ),

              // Bottom Sticky Cart Summary Bar
              BlocBuilder<CartBloc, CartState>(
                builder: (context, state) {
                  if (!state.hasItems) return const SizedBox.shrink();

                  return Container(
                    decoration: const BoxDecoration(
                      color: AppColors.surface,
                      border: Border(
                        top: BorderSide(color: AppColors.border, width: 1),
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    child: Row(
                      children: [
                        // Clear button
                        InkWell(
                          onTap: () => _openClearCartDialog(context, state),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            height: 52,
                            width: 52,
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: AppColors.controlBorder,
                              ),
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.delete_outline,
                                color: AppColors.danger,
                                size: 22,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Continue button — straight to payment; customer
                        // details were already collected in step 1.
                        Expanded(
                          child: PrimaryButton(
                            label:
                                'Continue · ${CurrencyFormatter.format(state.totalAmount)} (${state.totalItemCount} ${state.totalItemCount == 1 ? "item" : "items"})',
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const CheckoutScreen(),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProductRow(
    BuildContext context, {
    required Product product,
    required CartItem? cartItem,
    required bool isAdded,
  }) {
    String priceDesc;
    if (product.isWeight) {
      if (product.slabs.isNotEmpty) {
        priceDesc =
            '${CurrencyFormatter.format(product.slabs.first.price)} / up to ${product.slabs.first.limit.toInt()}kg';
      } else {
        priceDesc = 'Per kg';
      }
    } else {
      priceDesc = CurrencyFormatter.format(product.price);
    }

    return Container(
      decoration: BoxDecoration(
        color: isAdded ? AppColors.selectedSurface : AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isAdded ? AppColors.primary : AppColors.border,
          width: isAdded ? 1.5 : 1.0,
        ),
        boxShadow: isAdded
            ? null
            : const [
                BoxShadow(
                  color: AppColors.shadow,
                  blurRadius: 2,
                  offset: Offset(0, 1),
                ),
              ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Left: Info & edit trigger
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  product.name,
                  style: const TextStyle(
                    fontFamily: AppTextStyles.fontBody,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    StatusPill(
                      label: product.isWeight ? 'Per kg' : 'Per piece',
                      variant: product.isWeight
                          ? PillVariant.inProgress
                          : PillVariant.neutral,
                    ),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        priceDesc,
                        style: AppTextStyles.hint.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (isAdded && cartItem != null) ...[
                  const SizedBox(height: 7),
                  InkWell(
                    onTap: () => _openEditDialog(context, cartItem),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          CurrencyFormatter.format(cartItem.computedAmount),
                          style: const TextStyle(
                            fontFamily: AppTextStyles.fontDisplay,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 5),
                        const Icon(
                          Icons.edit_outlined,
                          size: 14,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 3),
                        const Text(
                          'Edit',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(width: 12),

          // Right: Add Control or Stepper
          if (!isAdded)
            InkWell(
              onTap: () {
                if (product.isWeight) {
                  // Weighted: open dialog first — user must enter weight before adding
                  WeightedItemDialog.show(
                    context,
                    product: product,
                    onAdd: (weight) {
                      context.read<CartBloc>().add(
                        AddItemToCartEvent(product: product, quantity: weight),
                      );
                    },
                  );
                } else {
                  context.read<CartBloc>().add(
                    AddItemToCartEvent(product: product, quantity: 1.0),
                  );
                }
              },
              borderRadius: BorderRadius.circular(9),
              child: Container(
                constraints: const BoxConstraints(minWidth: 74, minHeight: 44),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: AppColors.primary, width: 1.5),
                ),
                alignment: Alignment.center,
                child: const Text(
                  'Add',
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontBody,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
            )
          else if (cartItem != null) ...[
            if (product.isWeight)
              InkWell(
                onTap: () => _openEditDialog(context, cartItem),
                borderRadius: BorderRadius.circular(9),
                child: Container(
                  constraints: const BoxConstraints(
                    minWidth: 106,
                    minHeight: 44,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: AppColors.primary, width: 1.5),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        QuantityFormatter.format(cartItem.quantity),
                        style: const TextStyle(
                          fontFamily: AppTextStyles.fontDisplay,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Text(
                        'kg',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.mutedText,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              Container(
                constraints: const BoxConstraints(minHeight: 44),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: AppColors.primary, width: 1.5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      onTap: () {
                        context.read<CartBloc>().add(
                          UpdateItemQuantityEvent(
                            productId: product.id,
                            quantity: cartItem.quantity - 1,
                          ),
                        );
                      },
                      child: const SizedBox(
                        width: 38,
                        height: 44,
                        child: Center(
                          child: Icon(
                            Icons.remove,
                            size: 18,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ),
                    Container(
                      constraints: const BoxConstraints(minWidth: 32),
                      alignment: Alignment.center,
                      child: Text(
                        cartItem.quantity.toInt().toString(),
                        style: const TextStyle(
                          fontFamily: AppTextStyles.fontDisplay,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () {
                        context.read<CartBloc>().add(
                          UpdateItemQuantityEvent(
                            productId: product.id,
                            quantity: cartItem.quantity + 1,
                          ),
                        );
                      },
                      child: Container(
                        width: 38,
                        height: 44,
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.horizontal(
                            right: Radius.circular(7),
                          ),
                        ),
                        child: const Center(
                          child: Icon(Icons.add, size: 18, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
