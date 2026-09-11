class PricingSlab {
  final double limit; // weight limit in kg
  final int price; // total price for this slab

  PricingSlab({required this.limit, required this.price});

  factory PricingSlab.fromJson(Map<String, dynamic> json) {
    return PricingSlab(
      limit: (json['limit'] as num?)?.toDouble() ?? 0.0,
      price: (json['price'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {'limit': limit, 'price': price};
  }
}

class Product {
  final String id;
  final String name;
  final String category;
  final bool active;
  final String type; // 'item' | 'weight'
  final int price; // for item products
  final List<PricingSlab> slabs; // for weight products
  final int extra; // per kg extra above highest slab

  Product({
    required this.id,
    required this.name,
    required this.category,
    this.active = true,
    required this.type,
    this.price = 0,
    this.slabs = const [],
    this.extra = 0,
  });

  bool get isWeight => type.toLowerCase() == 'weight';
  bool get isItem => !isWeight;

  factory Product.fromJson(Map<String, dynamic> json) {
    final rawType = (json['type']?.toString().toLowerCase() ?? 'item');
    final rawSlabs = json['slabs'];
    List<PricingSlab> slabsList = [];
    if (rawSlabs is List) {
      slabsList =
          rawSlabs
              .map(
                (s) =>
                    PricingSlab.fromJson(Map<String, dynamic>.from(s as Map)),
              )
              .toList()
            ..sort((a, b) => a.limit.compareTo(b.limit));
    }

    return Product(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      category: json['category']?.toString() ?? 'wash',
      active: json['active'] != false,
      type: rawType,
      price: (json['price'] as num?)?.toInt() ?? 0,
      slabs: slabsList,
      extra: (json['extra'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    if (isWeight) {
      return {
        'id': id,
        'name': name,
        'category': category,
        'active': active,
        'type': 'weight',
        'slabs': slabs.map((s) => s.toJson()).toList(),
        'extra': extra,
      };
    }
    return {
      'id': id,
      'name': name,
      'category': category,
      'active': active,
      'type': 'item',
      'price': price,
    };
  }

  /// Exact price calculation matching server `src/server/pricing.ts`
  int computePrice(double quantity) {
    if (quantity <= 0) return 0;
    if (isItem) {
      return (price * quantity).round();
    }
    // Weight product calculation
    for (final slab in slabs) {
      if (quantity <= slab.limit) {
        return slab.price;
      }
    }
    if (slabs.isEmpty) return 0;
    final last = slabs.last;
    return (last.price + (quantity - last.limit) * extra).round();
  }
}
