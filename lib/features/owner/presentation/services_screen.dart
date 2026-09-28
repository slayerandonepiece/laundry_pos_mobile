import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:myshop/core/constants/app_colors.dart';
import 'package:myshop/core/theme/text_styles.dart';
import 'package:myshop/core/utils/currency_formatter.dart';
import 'package:myshop/core/utils/idempotency.dart';
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
  bool _isGridView = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadServices();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Opens from the local cache; the network only on [refresh] (pull to
  /// refresh, after a save) or when nothing is cached yet.
  Future<void> _loadServices({bool refresh = false}) async {
    final posRepository = context.read<PosRepository>();
    final cached = posRepository.getCachedProductsList();
    if (cached.isNotEmpty) {
      setState(() => _products = cached);
      if (!refresh) return;
    } else {
      setState(() => _isLoading = true);
    }
    try {
      final list = await posRepository.listProducts();
      if (!mounted) return;
      setState(() {
        _products = list;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not load services — try again'),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  List<Product> get _filteredProducts {
    if (_searchQuery.trim().isEmpty) return _products;
    final query = _searchQuery.trim().toLowerCase();
    return _products.where((p) {
      return p.name.toLowerCase().contains(query) ||
          p.category.toLowerCase().contains(query);
    }).toList();
  }

  void _showAddServiceDialog(BuildContext context) {
    final repo = context.read<OwnerRepository>();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RepositoryProvider.value(
          value: repo,
          child: ServiceFormScreen(onSaved: () => _loadServices(refresh: true)),
        ),
      ),
    );
  }

  void _showEditServiceDialog(BuildContext context, Product product) {
    final repo = context.read<OwnerRepository>();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RepositoryProvider.value(
          value: repo,
          child: ServiceFormScreen(
            product: product,
            onSaved: () => _loadServices(refresh: true),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredProducts;

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
              _searchQuery.isNotEmpty
                  ? '${filtered.length} of ${_products.length} services'
                  : '${_products.length} services configured',
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
          : Column(
              children: [
                // Search bar and view toggle
                Container(
                  color: AppColors.surface,
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
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
                                    hintText:
                                        'Search by service or category...',
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
                                  child: const Icon(
                                    Icons.close,
                                    size: 18,
                                    color: AppColors.mutedText,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Grid/List segmented toggle
                      Container(
                        height: 44,
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: AppColors.inset,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            InkWell(
                              onTap: () {
                                if (_isGridView) {
                                  setState(() => _isGridView = false);
                                }
                              },
                              borderRadius: BorderRadius.circular(7),
                              child: Container(
                                width: 36,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: !_isGridView
                                      ? AppColors.surface
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(7),
                                  boxShadow: !_isGridView
                                      ? [
                                          const BoxShadow(
                                            color: Color(0x10000000),
                                            blurRadius: 3,
                                            offset: Offset(0, 1),
                                          ),
                                        ]
                                      : null,
                                ),
                                child: Icon(
                                  Icons.view_list_rounded,
                                  size: 20,
                                  color: !_isGridView
                                      ? AppColors.primary
                                      : AppColors.mutedText,
                                ),
                              ),
                            ),
                            const SizedBox(width: 2),
                            InkWell(
                              onTap: () {
                                if (!_isGridView) {
                                  setState(() => _isGridView = true);
                                }
                              },
                              borderRadius: BorderRadius.circular(7),
                              child: Container(
                                width: 36,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: _isGridView
                                      ? AppColors.surface
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(7),
                                  boxShadow: _isGridView
                                      ? [
                                          const BoxShadow(
                                            color: Color(0x10000000),
                                            blurRadius: 3,
                                            offset: Offset(0, 1),
                                          ),
                                        ]
                                      : null,
                                ),
                                child: Icon(
                                  Icons.grid_view_rounded,
                                  size: 18,
                                  color: _isGridView
                                      ? AppColors.primary
                                      : AppColors.mutedText,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () => _loadServices(refresh: true),
                    child: filtered.isEmpty
                        ? ListView(
                            padding: const EdgeInsets.all(40),
                            children: [
                              Center(
                                child: Text(
                                  _searchQuery.isNotEmpty
                                      ? 'No services match "$_searchQuery"'
                                      : 'No services configured yet',
                                  style: AppTextStyles.hint,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          )
                        : _isGridView
                        ? GridView.builder(
                            padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 12,
                                  childAspectRatio: 1.15,
                                ),
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final product = filtered[index];
                              return _ServiceGridCard(
                                product: product,
                                onEdit: () =>
                                    _showEditServiceDialog(context, product),
                              );
                            },
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
                            itemCount: filtered.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final product = filtered[index];
                              return _ServiceCard(
                                product: product,
                                onEdit: () =>
                                    _showEditServiceDialog(context, product),
                              );
                            },
                          ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _ServiceGridCard extends StatelessWidget {
  final Product product;
  final VoidCallback onEdit;

  const _ServiceGridCard({required this.product, required this.onEdit});

  String get _startingPriceLabel {
    if (product.isWeight) {
      if (product.slabs.isNotEmpty) {
        return 'From ${CurrencyFormatter.format(product.slabs.first.price)}';
      } else if (product.extra > 0) {
        return '${CurrencyFormatter.format(product.extra)} / kg';
      }
      return 'Weight pricing';
    }
    return '${CurrencyFormatter.format(product.price)} / pc';
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(12),
      onTap: onEdit,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  StatusPill(
                    label: product.active ? 'Active' : 'Inactive',
                    variant: product.active
                        ? PillVariant.delivered
                        : PillVariant.neutral,
                  ),
                  const Icon(
                    Icons.north_east,
                    size: 14,
                    color: AppColors.mutedText,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                product.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: AppTextStyles.fontBody,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                product.category.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.hint.copyWith(fontSize: 10),
              ),
            ],
          ),
          Text(
            _startingPriceLabel,
            style: const TextStyle(
              fontFamily: AppTextStyles.fontDisplay,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ServiceCard extends StatelessWidget {
  final Product product;
  final VoidCallback onEdit;

  const _ServiceCard({required this.product, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(16),
      onTap: onEdit,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: name, status pills & edit action
          // Header: Name and Edit pricing
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  product.name,
                  style: const TextStyle(
                    fontFamily: AppTextStyles.fontBody,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: onEdit,
                borderRadius: BorderRadius.circular(6),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Edit pricing',
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontBody,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                      SizedBox(width: 3),
                      Icon(
                        Icons.north_east,
                        size: 13,
                        color: AppColors.primary,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Pills & Category taking full card width
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              StatusPill(
                label: product.isWeight ? 'Per kg' : 'Per piece',
                variant: product.isWeight
                    ? PillVariant.inProgress
                    : PillVariant.neutral,
              ),
              StatusPill(
                label: product.active ? 'Active' : 'Inactive',
                variant: product.active
                    ? PillVariant.delivered
                    : PillVariant.neutral,
              ),
              Text(
                product.category.toUpperCase(),
                style: AppTextStyles.hint.copyWith(fontSize: 11),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),

          // Divider
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(color: AppColors.divider, height: 1),
          ),

          // Tier breakdown
          if (product.isWeight) ...[
            if (product.slabs.isEmpty && product.extra <= 0)
              Text('No pricing tiers configured', style: AppTextStyles.hint)
            else ...[
              for (final slab in product.slabs)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Up to ${slab.limit % 1 == 0 ? slab.limit.toInt() : slab.limit} kg',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.mutedText,
                        ),
                      ),
                      Text(
                        CurrencyFormatter.format(slab.price),
                        style: const TextStyle(
                          fontFamily: AppTextStyles.fontDisplay,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text,
                        ),
                      ),
                    ],
                  ),
                ),
              if (product.extra > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Extra kg',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.mutedText,
                        ),
                      ),
                      Text(
                        '${CurrencyFormatter.format(product.extra)} / kg',
                        style: const TextStyle(
                          fontFamily: AppTextStyles.fontDisplay,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ] else ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Per piece',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.mutedText,
                  ),
                ),
                Text(
                  CurrencyFormatter.format(product.price),
                  style: const TextStyle(
                    fontFamily: AppTextStyles.fontDisplay,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _TierEntry {
  final TextEditingController limitController;
  final TextEditingController priceController;

  _TierEntry({String limit = '', String price = ''})
    : limitController = TextEditingController(text: limit),
      priceController = TextEditingController(text: price);

  void dispose() {
    limitController.dispose();
    priceController.dispose();
  }
}

class ServiceFormScreen extends StatefulWidget {
  final Product? product;
  final VoidCallback onSaved;

  const ServiceFormScreen({super.key, this.product, required this.onSaved});

  @override
  State<ServiceFormScreen> createState() => _ServiceFormScreenState();
}

class _ServiceFormScreenState extends State<ServiceFormScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _priceController;
  late final TextEditingController _extraController;
  final ScrollController _scrollController = ScrollController();
  late String _category;
  late String _unit;
  late bool _active;
  late List<_TierEntry> _tiers;
  bool _isSaving = false;
  String? _errorMessage;
  late final String _productId =
      widget.product?.id ?? IdempotencyKeyGenerator.generate();

  bool get _isEditing => widget.product != null;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _nameController = TextEditingController(text: p?.name ?? '');
    final initialCat = p?.category.trim();
    _category = (initialCat != null && initialCat.isNotEmpty)
        ? initialCat
        : 'wash';
    _unit = p != null ? (p.isWeight ? 'WEIGHT' : 'PIECE') : 'PIECE';
    _active = p?.active ?? true;

    final priceStr = p != null && p.isItem
        ? (p.price / 100).toStringAsFixed(p.price % 100 == 0 ? 0 : 2)
        : '';
    _priceController = TextEditingController(text: priceStr);

    final extraStr = p != null && p.isWeight && p.extra > 0
        ? (p.extra / 100).toStringAsFixed(p.extra % 100 == 0 ? 0 : 2)
        : '';
    _extraController = TextEditingController(text: extraStr);

    if (p != null && p.isWeight && p.slabs.isNotEmpty) {
      _tiers = p.slabs
          .map(
            (s) => _TierEntry(
              limit: s.limit % 1 == 0
                  ? s.limit.toInt().toString()
                  : s.limit.toString(),
              price: (s.price / 100).toStringAsFixed(
                s.price % 100 == 0 ? 0 : 2,
              ),
            ),
          )
          .toList();
    } else {
      _tiers = [_TierEntry()];
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _extraController.dispose();
    _scrollController.dispose();
    for (final t in _tiers) {
      t.dispose();
    }
    super.dispose();
  }

  Future<void> _handleSave() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _errorMessage = 'Please enter a service name.');
      return;
    }

    final slabs = <Map<String, dynamic>>[];
    int priceInPaise = 0;
    int? extraInPaise;

    if (_unit == 'WEIGHT') {
      for (final t in _tiers) {
        final limit = double.tryParse(t.limitController.text.trim()) ?? 0;
        final priceRupees = double.tryParse(t.priceController.text.trim()) ?? 0;
        if (limit > 0 && priceRupees > 0) {
          slabs.add({'limit': limit, 'price': (priceRupees * 100).round()});
        }
      }

      if (slabs.isEmpty) {
        setState(() {
          _errorMessage =
              'Please add at least one valid tier with weight limit and price.';
        });
        return;
      }
      slabs.sort((a, b) => (a['limit'] as num).compareTo(b['limit'] as num));
      priceInPaise = slabs.first['price'] as int;

      final extraRupees = double.tryParse(_extraController.text.trim()) ?? 0;
      extraInPaise = extraRupees > 0 ? (extraRupees * 100).round() : 0;
    } else {
      final priceRupees = double.tryParse(_priceController.text.trim()) ?? 0;
      priceInPaise = (priceRupees * 100).round();
      if (priceInPaise <= 0) {
        setState(() => _errorMessage = 'Please enter a valid price.');
        return;
      }
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      if (_isEditing) {
        await context.read<OwnerRepository>().updateProduct(
          id: widget.product!.id,
          name: name,
          category: _category,
          unit: _unit,
          price: priceInPaise,
          slabs: _unit == 'WEIGHT' ? slabs : const [],
          active: _active,
          extra: extraInPaise,
        );
      } else {
        await context.read<OwnerRepository>().createProduct(
          id: _productId,
          name: name,
          category: _category,
          unit: _unit,
          price: priceInPaise,
          slabs: _unit == 'WEIGHT' ? slabs : const [],
          active: _active,
          extra: extraInPaise,
        );
      }

      if (!mounted) return;
      Navigator.pop(context);
      widget.onSaved();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorMessage = 'Failed to save service. Please try again.';
      });
    }
  }

  List<String> get _categoryOptions {
    const defaultOptions = ['wash', 'dry clean', 'iron', 'premium', 'laundry'];
    final candidates = <String>[...defaultOptions];
    final prodCat = widget.product?.category.trim();
    if (prodCat != null &&
        prodCat.isNotEmpty &&
        !candidates.any((c) => c.toLowerCase() == prodCat.toLowerCase())) {
      candidates.add(prodCat);
    }
    if (_category.isNotEmpty &&
        !candidates.any((c) => c.toLowerCase() == _category.toLowerCase())) {
      candidates.add(_category);
    }

    final options = <String>[];
    for (final opt in candidates) {
      if (opt.toLowerCase() == _category.toLowerCase()) {
        options.add(_category);
      } else if (prodCat != null &&
          opt.toLowerCase() == prodCat.toLowerCase()) {
        options.add(prodCat);
      } else {
        options.add(opt);
      }
    }
    return options;
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
        title: Text(
          _isEditing ? 'Edit pricing' : 'Add service',
          style: const TextStyle(
            fontFamily: AppTextStyles.fontDisplay,
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
            color: AppColors.text,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: AppColors.border, height: 1),
        ),
      ),
      body: SingleChildScrollView(
        controller: _scrollController,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Service name
            AppTextField(
              label: 'SERVICE NAME',
              hint: 'e.g. Silk Saree Dry Clean',
              controller: _nameController,
            ),
            const SizedBox(height: 14),

            // Category and Unit Type
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _category,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'CATEGORY',
                      labelStyle: AppTextStyles.fieldLabel,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 14,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    items: _categoryOptions
                        .map(
                          (c) => DropdownMenuItem(
                            value: c,
                            child: Text(
                              c.toUpperCase(),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onTap: () => FocusScope.of(context).unfocus(),
                    onChanged: (v) {
                      if (v != null) {
                        setState(() => _category = v);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _unit,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'UNIT TYPE',
                      labelStyle: AppTextStyles.fieldLabel,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 14,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'PIECE',
                        child: Text(
                          'Per piece',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'WEIGHT',
                        child: Text('Per kg', overflow: TextOverflow.ellipsis),
                      ),
                    ],
                    onTap: () => FocusScope.of(context).unfocus(),
                    onChanged: (v) {
                      if (v != null) {
                        setState(() => _unit = v);
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Status Switch (Active / Inactive)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.inset,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Service status',
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontBody,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.text,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _active
                              ? 'Active · Available for new orders'
                              : 'Inactive · Hidden from new orders',
                          style: AppTextStyles.hint,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Switch(
                    value: _active,
                    activeThumbColor: AppColors.primary,
                    onChanged: (v) => setState(() => _active = v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Unit specific pricing section
            if (_unit == 'PIECE') ...[
              AppTextField(
                label: 'PRICE PER PIECE (₹)',
                hint: 'e.g. 150',
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                controller: _priceController,
              ),
            ] else ...[
              // Weight Pricing Tiers
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'PRICING TIERS',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontBody,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.mutedText,
                      letterSpacing: 0.5,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _tiers.add(_TierEntry());
                      });
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (_scrollController.hasClients) {
                          _scrollController.animateTo(
                            _scrollController.position.maxScrollExtent,
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeOut,
                          );
                        }
                      });
                    },
                    icon: const Icon(
                      Icons.add,
                      size: 16,
                      color: AppColors.primary,
                    ),
                    label: const Text(
                      'Add tier',
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontBody,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Table header for tiers
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 2),
                child: Row(
                  children: [
                    Expanded(
                      flex: 5,
                      child: Text('UP TO (KG)', style: AppTextStyles.label),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      flex: 5,
                      child: Text('PRICE (₹)', style: AppTextStyles.label),
                    ),
                    SizedBox(width: 36),
                  ],
                ),
              ),
              const SizedBox(height: 6),

              // Editable tier rows
              ..._tiers.asMap().entries.map((entry) {
                final index = entry.key;
                final tier = entry.value;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 5,
                        child: AppTextField(
                          hint: 'e.g. 4',
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          controller: tier.limitController,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 5,
                        child: AppTextField(
                          hint: 'e.g. 200',
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          controller: tier.priceController,
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        constraints: const BoxConstraints(
                          minWidth: 36,
                          minHeight: 36,
                        ),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(
                          Icons.remove_circle_outline,
                          color: AppColors.danger,
                          size: 22,
                        ),
                        tooltip: 'Remove tier',
                        onPressed: _tiers.length > 1
                            ? () {
                                setState(() {
                                  final removed = _tiers.removeAt(index);
                                  removed.dispose();
                                });
                              }
                            : null,
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 8),

              // Extra per kg field
              AppTextField(
                label: 'EXTRA RATE PER KG (₹)',
                hint: 'e.g. 40 (rate above final slab)',
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                controller: _extraController,
              ),
            ],

            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                style: const TextStyle(
                  fontFamily: AppTextStyles.fontBody,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.danger,
                ),
              ),
            ],

            const SizedBox(height: 20),
            PrimaryButton(
              label: _isEditing ? 'Save changes' : 'Create service',
              isLoading: _isSaving,
              onPressed: _isSaving ? null : _handleSave,
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
