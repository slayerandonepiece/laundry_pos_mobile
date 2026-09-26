class StorePaymentMethod {
  final String id;
  final String code;
  final String name;
  final String type;
  final bool active;

  StorePaymentMethod({
    required this.id,
    this.code = '',
    required this.name,
    String? type,
    this.active = true,
  }) : type = type ?? (name.toUpperCase().contains('UPI') ? 'UPI' : 'Cash');

  factory StorePaymentMethod.fromJson(Map<String, dynamic> json) {
    final name = json['name']?.toString() ?? '';
    return StorePaymentMethod(
      id: json['id']?.toString() ?? '',
      code: json['code']?.toString() ?? '',
      name: name,
      type:
          json['type']?.toString() ??
          (name.toUpperCase().contains('UPI') ? 'UPI' : 'Cash'),
      active: (json['active'] ?? json['enabled']) != false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'code': code,
      'name': name,
      'type': type,
      'active': active,
    };
  }
}
