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
  }) : type = type ?? (code.isNotEmpty ? code : '');

  factory StorePaymentMethod.fromJson(Map<String, dynamic> json) {
    final code = json['code']?.toString() ?? '';
    return StorePaymentMethod(
      id: json['id']?.toString() ?? '',
      code: code,
      name: json['name']?.toString() ?? '',
      type: json['type']?.toString() ?? (code.isNotEmpty ? code : ''),
      active: (json['active'] ?? json['enabled']) != false,
    );
  }

  bool get isCashOnDelivery {
    final value = (code.trim().isNotEmpty ? code : name)
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]'), '');
    return value == 'COD' || value == 'CASHONDELIVERY';
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
