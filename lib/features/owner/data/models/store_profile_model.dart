class StoreProfile {
  final String store; // Store name
  final String address;
  final String phone;
  final String email;
  final String name; // Owner name

  StoreProfile({
    required this.store,
    required this.address,
    required this.phone,
    this.email = '',
    required this.name,
  });

  String get storeName => store;

  factory StoreProfile.fromJson(Map<String, dynamic> json) {
    return StoreProfile(
      store: json['store']?.toString() ?? '',
      address: json['address']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'store': store,
      'address': address,
      'phone': phone,
      'email': email,
      'name': name,
    };
  }
}
